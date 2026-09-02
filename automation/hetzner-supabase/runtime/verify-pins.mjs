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
  assert.match(image, digestPattern, `${name} must be pinned by tag and arm64 digest`);
}
for (const [name, source] of Object.entries(pins.sources)) {
  assert.match(source, /^https:\/\//, `${name} must cite an HTTPS primary source`);
}
process.stdout.write(`runtime pins valid: ${pins.supabase.release}, ${Object.keys(pins.supabase.images).length} immutable images\n`);

if (process.argv.includes('--online')) await verifyOnline();

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
    if (name !== 'caddy') assert.ok(composeImages.has(pinned.split('@')[0]), `${name} is not in the selected Supabase bundle`);
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
