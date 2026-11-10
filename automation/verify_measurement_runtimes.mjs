import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
import {runtimeSource} from '../workers/form-measurement/src/runtime_source.mjs';
import {readRuntimes} from './lib/measurement_runtimes.mjs';
import {measurementBuildId} from './lib/measurement_build.mjs';

export const sha256 = value => createHash('sha256').update(value).digest('hex');

export async function verifyRuntimes(entries, {
  fetchImpl = globalThis.fetch, wait = delay, attempts = 4, retryMs = 5000,
  expectedBuildId,
  timeoutMs = 10000, expectedSource = runtimeSource, log = console.log,
} = {}) {
  expectedBuildId ??= await measurementBuildId();
  const expected = sha256(expectedSource);
  const results = [];
  for (const {project} of entries) {
    let actual = null, actualBuildId = null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      actual = null; actualBuildId = null;
      try {
        const response = await fetchImpl(`https://${project}.pages.dev/runtime.js`, {
          signal: AbortSignal.timeout(timeoutMs), redirect: 'error', cache: 'no-store',
        });
        if (response.ok) {
          actual = sha256(Buffer.from(await response.arrayBuffer()));
          const header = response.headers.get('x-festapp-runtime-build');
          actualBuildId = /^[a-f0-9]{64}$/.test(header ?? '') ? header : null;
        }
      } catch { /* Public probe only; never log arbitrary remote error/body content. */ }
      if (actual === expected && actualBuildId === expectedBuildId) break;
      if (attempt + 1 < attempts) await wait(retryMs);
    }
    const ok = actual === expected && actualBuildId === expectedBuildId;
    log(`${project} expected=${expected.slice(0, 12)} actual=${actual?.slice(0, 12) ?? 'unavailable'} build=${expectedBuildId.slice(0, 12)}/${actualBuildId?.slice(0, 12) ?? 'unavailable'} ${ok ? 'OK' : 'DRIFT'}`);
    results.push({project, expected, actual, expectedBuildId, actualBuildId, ok});
  }
  return results;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2);
    if (args.length && (args.length !== 2 || args[0] !== '--only')) throw Error('Usage: verify_measurement_runtimes.mjs [--only <project>]');
    const results = await verifyRuntimes(await readRuntimes(args[1]));
    if (results.some(result => !result.ok)) process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
