import { readFile, appendFile, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { basename, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { gunzipSync } from 'node:zlib';

export async function planNpmRelease(folder, { sourceCommit, packageName, version, fetchRegistry = fetch }) {
  if (!/^[a-f0-9]{40}$/i.test(sourceCommit ?? '')) throw new Error('A complete source commit is required');
  const readJson = async (name) => JSON.parse(await readFile(resolve(folder, name), 'utf8'));
  const receipt = await readJson('archive-result.json');
  if (receipt.sourceCommit !== sourceCommit || ![
    'passed', 'coreSourceByteEquivalent', 'pubSelectedCoreAndWrapper',
    'actualNpmPack', 'archivedExampleBuilt', 'archivedExampleBrowser',
  ].every((gate) => receipt[gate] === true)) {
    throw new Error('The npm archive is not verified for this source commit');
  }
  const packs = await readJson('npm-pack.json');
  if (packs.length !== 1 || packs[0].name !== packageName || packs[0].version !== version ||
      basename(packs[0].filename) !== packs[0].filename || !packs[0].filename.endsWith('.tgz')) {
    throw new Error('The verified npm archive does not match the selected package version');
  }
  let archive = resolve(folder, packs[0].filename);
  const archiveBytes = await readFile(archive);
  const response = await fetchRegistry(`https://registry.npmjs.org/${encodeURIComponent(packageName)}/${encodeURIComponent(version)}`);
  if (response.status !== 200 && response.status !== 404) {
    throw new Error(`npm version lookup failed: HTTP ${response.status}`);
  }
  if (response.status === 200) {
    const published = await response.json();
    const integrity = 'sha512-' + createHash('sha512').update(archiveBytes).digest('base64');
    if (published.dist?.integrity !== integrity) {
      const conflict = 'This npm version already exists with different archive bytes; select a new version';
      if (!published.dist?.tarball) throw new Error(conflict);
      const location = new URL(published.dist.tarball);
      if (location.origin !== 'https://registry.npmjs.org' ||
          !decodeURIComponent(location.pathname).startsWith(`/${packageName}/-/`)) {
        throw new Error('Unexpected npm registry archive location');
      }
      const download = await fetchRegistry(location.href);
      if (download.status !== 200) throw new Error(`npm archive lookup failed: HTTP ${download.status}`);
      const publishedBytes = Buffer.from(await download.arrayBuffer());
      if ('sha512-' + createHash('sha512').update(publishedBytes).digest('base64') !== published.dist.integrity) {
        throw new Error('The published npm archive does not match its registry integrity');
      }
      // Different gzip encoders may wrap exactly the same tar bytes. Compare
      // the entire tar payload, including paths and metadata, without repacking.
      const options = { maxOutputLength: 64 * 1024 * 1024 };
      if (!gunzipSync(publishedBytes, options).equals(gunzipSync(archiveBytes, options))) throw new Error(conflict);
      const digest = createHash('sha256').update(publishedBytes).digest('hex').slice(0, 12);
      const retained = resolve(folder, `${basename(packs[0].filename, '.tgz')}-registry-${digest}.tgz`);
      try {
        await writeFile(retained, publishedBytes, { flag: 'wx' });
      } catch (error) {
        if (error.code !== 'EEXIST' || !(await readFile(retained)).equals(publishedBytes)) throw error;
      }
      archive = retained;
    }
  }
  return { archive, publish: response.status === 404 };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const { name: packageName, version } = JSON.parse(await readFile(new URL('../web/package.json', import.meta.url), 'utf8'));
  const plan = await planNpmRelease(process.argv[2], { sourceCommit: process.env.GITHUB_SHA, packageName, version });
  await appendFile(process.env.GITHUB_OUTPUT, `publish=${plan.publish}\narchive=${plan.archive}\n`);
  console.log(plan.publish ? `Publish verified ${packageName}@${version}` : `${packageName}@${version} is already published; skipping`);
}
