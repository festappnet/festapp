#!/usr/bin/env node
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';

const manifestPath = new URL('./pins.json', import.meta.url);
const pins = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
const digestPattern = /^[a-z0-9./_-]+:[A-Za-z0-9._-]+@sha256:[a-f0-9]{64}$/;
const versionPattern = /^\d+(?:\.\d+)+(?: LTS)?$/;

assert.equal(pins.manifestVersion, 1);
assert.equal(pins.architecture, 'linux/arm64');
assert.equal(pins.supabase.registryEvidence.platform, pins.architecture);
assert.equal(pins.policy, 'latest-stable-compatible-bundle');
assert.match(pins.supabase.release, /^self-hosted\/v\d+\.\d+\.\d+$/);
assert.match(pins.supabase.commit, /^[a-f0-9]{40}$/);
assert.equal(pins.supabase.postgresMajor, 17);
assert.ok(!stableJson(pins).toLowerCase().includes(':latest'));
for (const [name, version] of Object.entries(pins.host)) {
  assert.match(version, versionPattern, `${name} must be an exact stable version`);
}
for (const [name, image] of Object.entries(pins.supabase.images)) {
  assert.ok(!['storage', 'imgproxy'].includes(name), `${name} is retired from the active runtime`);
  assert.match(image, digestPattern, `${name} must be pinned by tag and arm64 digest`);
}
assert.deepEqual(Object.keys(pins.supabase.historicalBackupImages), ['storage']);
assert.match(pins.supabase.historicalBackupImages.storage, digestPattern);
for (const [name, source] of Object.entries(pins.sources)) {
  assert.match(source, /^https:\/\//, `${name} must cite an HTTPS primary source`);
}
if (pins.supabase.postgresOverride) {
  const override = pins.supabase.postgresOverride;
  assert.equal(override.image, pins.supabase.images.postgres);
  assert.equal(override.bundleImage, 'supabase/postgres:17.6.1.136');
  assert.equal(override.releaseCommit, '95eeb9f21d83a473b38036e1da70c31bc597418a');
  assert.equal(override.image, 'supabase/postgres:17.12.0.000@sha256:6c056e9a0f81d423c1a81fdf4e6587c16efd3f63960897371dab8ae2694a4714');
  assert.equal(override.evidence, 'docs/operations/supabase-self-hosted/runtime-update-20261115/postgres-compatibility.json');
  const evidence = JSON.parse(fs.readFileSync(new URL(`../../../${override.evidence}`, import.meta.url)));
  assert.equal(evidence.status, 'pass');
  assert.equal(evidence.postgres_version_num, 170012);
  assert.equal(evidence.installed_config.status, 'pass');
  assert.equal(evidence.new_backup.status, 'pass');
  assert.equal(evidence.vault_keys.old_new_decryption_digest_equal, true);
}
process.stdout.write(`runtime pins valid: ${pins.supabase.release}, ${Object.keys(pins.supabase.images).length} immutable images\n`);

if (process.argv.includes('--online')) await verifyOnline();
else if (process.argv.includes('--bundle')) await verifySelectedBundle();

async function verifySelectedBundle() {
  const ref = await fetchJson(`https://api.github.com/repos/supabase/supabase/git/ref/tags/${pins.supabase.release}`);
  const commit = ref.object.type === 'tag' ? (await fetchJson(ref.object.url)).object.sha : ref.object.sha;
  assert.equal(commit, pins.supabase.commit, 'Selected Supabase tag/commit mismatch');
  const response = await fetch(`https://raw.githubusercontent.com/supabase/supabase/${commit}/docker/docker-compose.yml`).then(assertResponse);
  await verifyImages(await response.text());
  process.stdout.write('selected Supabase bundle and explicit PostgreSQL override verified; host tools unchanged\n');
}

async function verifyImages(compose) {
  const images = new Set(compose.split(/\r?\n/).map(line => line.match(/^\s+image:\s+(\S+)$/)?.[1]).filter(Boolean));
  for (const [name, pinned] of Object.entries(pins.supabase.images)) {
    if (!['caddy', 'cloudflared'].includes(name)) {
      const selected = name === 'postgres' && pins.supabase.postgresOverride
        ? pins.supabase.postgresOverride.bundleImage : pinned.split('@')[0];
      assert.ok(images.has(selected), `${name} is not in the selected Supabase bundle`);
    }
    if (process.argv.includes('--registry') && !['caddy', 'cloudflared'].includes(name)) {
      const inspected = JSON.parse(execFileSync('docker', ['manifest', 'inspect', '--verbose', pinned.split('@')[0]], { encoding: 'utf8' }));
      const manifests = Array.isArray(inspected) ? inspected : [inspected];
      const arm64 = manifests.find(value => value.Descriptor?.platform?.os === 'linux' && value.Descriptor?.platform?.architecture === 'arm64');
      assert.ok(arm64, `${name} has no linux/arm64 registry manifest`);
      assert.equal(arm64.Descriptor.digest, pinned.split('@')[1], `${name} arm64 digest changed`);
    }
  }
}

async function verifyOnline() {
  const latestRepositories = {
    dockerCompose: 'docker/compose',
    caddy: 'caddyserver/caddy',
    terraform: 'hashicorp/terraform',
    hcloudProvider: 'hetznercloud/terraform-provider-hcloud',
  };
  for (const [name, repository] of Object.entries(latestRepositories)) {
    const release = await fetchJson(`https://api.github.com/repos/${repository}/releases/latest`);
    assert.equal(release.prerelease, false, `${name} latest release must be stable`);
    assert.equal(release.draft, false, `${name} latest release must be published`);
    assert.equal(release.tag_name.replace(/^v/, ''), pins.host[name], `${name} is no longer latest stable`);
  }

  const refs = await fetchJson('https://api.github.com/repos/supabase/supabase/git/matching-refs/tags/self-hosted/v');
  const latestRef = refs.map((value) => value.ref.replace('refs/tags/', ''))
    .filter((value) => /^self-hosted\/v\d+\.\d+\.\d+$/.test(value))
    .sort(compareReleaseTags).at(-1);
  assert.equal(latestRef, pins.supabase.release, 'Supabase bundle is no longer latest stable');
  const tagRef = refs.find((value) => value.ref === `refs/tags/${latestRef}`);
  const commit = tagRef.object.type === 'tag'
    ? (await fetchJson(tagRef.object.url)).object.sha
    : tagRef.object.sha;
  assert.equal(commit, pins.supabase.commit, 'Supabase release commit changed');

  const compose = await fetch(`https://raw.githubusercontent.com/supabase/supabase/${pins.supabase.release}/docker/docker-compose.yml`).then(assertResponse);
  const composeImages = new Set((await compose.text()).split(/\r?\n/)
    .map((line) => line.match(/^\s+image:\s+(\S+)$/)?.[1]).filter(Boolean));
  for (const [name, pinned] of Object.entries(pins.supabase.images)) {
    if (!['caddy', 'cloudflared'].includes(name)) {
      const selected = name === 'postgres' && pins.supabase.postgresOverride
        ? pins.supabase.postgresOverride.bundleImage : pinned.split('@')[0];
      assert.ok(composeImages.has(selected), `${name} is not in the selected Supabase bundle`);
    }
    if (process.argv.includes('--registry')) {
      let inspected;
      try {
        inspected = JSON.parse(execFileSync('docker', ['manifest', 'inspect', '--verbose', pinned.split('@')[0]], { encoding: 'utf8' }));
      } catch (error) {
        throw new Error(`${name} registry verification failed; authenticate Docker before the provisioning gate: ${error.message}`);
      }
      const manifests = Array.isArray(inspected) ? inspected : [inspected];
      const arm64 = manifests.find((value) => value.Descriptor?.platform?.os === 'linux' && value.Descriptor?.platform?.architecture === 'arm64');
      assert.ok(arm64, `${name} has no linux/arm64 registry manifest`);
      assert.equal(arm64.Descriptor.digest, pinned.split('@')[1], `${name} arm64 digest changed`);
    }
  }

  const [ubuntu, dockerReleaseNotes, postgres] = await Promise.all([
    fetch('https://ubuntu.com/download/server').then(assertResponse).then((value) => value.text()),
    fetch('https://raw.githubusercontent.com/docker/docs/main/content/manuals/engine/release-notes/29.md').then(assertResponse).then((value) => value.text()),
    fetch('https://www.postgresql.org/docs/release/').then(assertResponse).then((value) => value.text()),
  ]);
  // Canonical may publish a point-release heading (for example 26.04.1 LTS),
  // while the provisioned host contract intentionally pins the LTS track.
  const ubuntuTrack = ubuntu.match(/Ubuntu (\d+\.\d+)(?:\.\d+)? LTS/)?.[1];
  const latestUbuntu = ubuntuTrack ? `${ubuntuTrack} LTS` : undefined;
  const latestDocker = dockerReleaseNotes.match(/^## (\d+\.\d+\.\d+)$/m)?.[1];
  const latestPostgres = postgres.match(/PostgreSQL (\d+\.\d+)/)?.[1];
  assert.equal(latestUbuntu, pins.host.ubuntu, 'Ubuntu pin is no longer the latest official LTS');
  assert.equal(latestDocker, pins.host.dockerEngine, 'Docker Engine pin is no longer the first stable v29 release');
  assert.equal(latestPostgres, pins.supabase.upstreamPostgresLatestStable, 'upstream PostgreSQL stable reference is stale');
  process.stdout.write(`online stable release pins verified against primary upstreams${process.argv.includes('--registry') ? ' and arm64 registries' : ''}\n`);
}

async function fetchJson(url) {
  return fetch(url, { headers: { accept: 'application/vnd.github+json', 'user-agent': 'festapp-runtime-pin-verifier' } })
    .then(assertResponse).then((response) => response.json());
}

function assertResponse(response) {
  if (!response.ok) throw new Error(`upstream verification failed: HTTP ${response.status} ${response.url}`);
  return response;
}

function compareReleaseTags(left, right) {
  const parse = (value) => value.match(/v(\d+)\.(\d+)\.(\d+)$/).slice(1).map(Number);
  const a = parse(left);
  const b = parse(right);
  return a[0] - b[0] || a[1] - b[1] || a[2] - b[2];
}

function stableJson(value) {
  if (Array.isArray(value)) return `[${value.map(stableJson).join(',')}]`;
  if (value && typeof value === 'object') {
    return `{${Object.keys(value).sort().map((key) => `${JSON.stringify(key)}:${stableJson(value[key])}`).join(',')}}`;
  }
  return JSON.stringify(value);
}
