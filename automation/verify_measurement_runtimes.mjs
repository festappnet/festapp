import {createHash} from 'node:crypto';
import {setTimeout as delay} from 'node:timers/promises';
import {pathToFileURL} from 'node:url';
import {runtimeSource} from '../workers/form-measurement/src/runtime_source.mjs';
import {readRuntimes} from './lib/measurement_runtimes.mjs';
import {measurementBuildId} from './lib/measurement_build.mjs';
import {measurementManifest, sameMeasurementManifest} from '../web_client/src/components/forms/form_measurement_contract.js';

export const sha256 = value => createHash('sha256').update(value).digest('hex');

async function probeRuntime(entry, fetchImpl, timeoutMs, expectedBuildId) {
  if (!entry.probe) return null; // Explicit initial provisioning, never a web-release proof.
  const url = new URL(`https://${entry.project}.pages.dev/runtime`);
  url.searchParams.set('form', entry.probe.form);
  url.searchParams.set('parent', entry.probe.parent);
  const response = await fetchImpl(url.href, {signal: AbortSignal.timeout(timeoutMs), redirect: 'error', cache: 'no-store'});
  if (!response.ok || !response.headers.get('content-type')?.startsWith('text/html') ||
      response.headers.get('x-festapp-runtime-build') !== expectedBuildId) return false;
  const text = await response.text();
  const match = text.match(/<script type="application\/json" id="measurement-config">([^<]*)<\/script>/);
  if (!match) return false;
  const boot = JSON.parse(match[1]);
  const manifest = measurementManifest(boot.manifest, entry.probe.form);
  const csp = response.headers.get('content-security-policy') ?? '';
  const ancestors = csp.split(';').map(part => part.trim().split(/\s+/)).find(parts => parts[0] === 'frame-ancestors');
  return boot.organization === entry.organization && boot.unit === entry.unit &&
    boot.form_link === entry.probe.form && boot.parent_origin === entry.probe.parent &&
    manifest?.organization === entry.organization && manifest?.unit === entry.unit &&
    sameMeasurementManifest(boot.manifest, manifest) && ancestors?.includes(entry.probe.parent) === true;
}

export async function verifyRuntimes(entries, {
  fetchImpl = globalThis.fetch, wait = delay, attempts = 4, retryMs = 5000,
  expectedBuildId,
  timeoutMs = 10000, expectedSource = runtimeSource, log = console.log, requireProbe = false,
} = {}) {
  expectedBuildId ??= await measurementBuildId();
  const expected = sha256(expectedSource);
  const results = [];
  for (const entry of entries) {
    const {project, organization, unit} = entry;
    let actual = null, actualBuildId = null, scopeOk = false, probeOk = entry.probe ? false : null;
    for (let attempt = 0; attempt < attempts; attempt++) {
      actual = null; actualBuildId = null; scopeOk = false; probeOk = entry.probe ? false : null;
      try {
        const response = await fetchImpl(`https://${project}.pages.dev/runtime.js`, {
          signal: AbortSignal.timeout(timeoutMs), redirect: 'error', cache: 'no-store',
        });
        if (response.ok) {
          actual = sha256(Buffer.from(await response.arrayBuffer()));
          const header = response.headers.get('x-festapp-runtime-build');
          actualBuildId = /^[a-f0-9]{64}$/.test(header ?? '') ? header : null;
          scopeOk = response.headers.get('x-festapp-runtime-organization') === String(organization) &&
            response.headers.get('x-festapp-runtime-unit') === String(unit) &&
            response.headers.get('x-festapp-runtime-backend') === 'https://api.festapp.net';
          if (actual === expected && actualBuildId === expectedBuildId && scopeOk) {
            probeOk = await probeRuntime(entry, fetchImpl, timeoutMs, expectedBuildId);
          }
        }
      } catch { /* Public probe only; never log arbitrary remote error/body content. */ }
      if (actual === expected && actualBuildId === expectedBuildId && scopeOk &&
          (probeOk === true || (!requireProbe && probeOk === null))) break;
      if (attempt + 1 < attempts) await wait(retryMs);
    }
    const ok = actual === expected && actualBuildId === expectedBuildId && scopeOk &&
      (probeOk === true || (!requireProbe && probeOk === null));
    log(`${project} expected=${expected.slice(0, 12)} actual=${actual?.slice(0, 12) ?? 'unavailable'} build=${expectedBuildId.slice(0, 12)}/${actualBuildId?.slice(0, 12) ?? 'unavailable'} scope=${scopeOk ? 'OK' : 'MISMATCH'} probe=${probeOk === null ? 'unconfigured' : probeOk ? 'OK' : 'FAILED'} ${ok ? 'OK' : 'DRIFT'}`);
    results.push({project, expected, actual, expectedBuildId, actualBuildId, scopeOk, probeOk, ok});
  }
  return results;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    const args = process.argv.slice(2);
    let only, organization, requireProbe = false;
    while (args.length) {
      const option = args.shift();
      if (option === '--require-probe') { requireProbe = true; continue; }
      if (!['--only', '--organization'].includes(option) || !args.length) throw Error('Invalid runtime verification arguments');
      const value = args.shift();
      if (option === '--only') only = value;
      else {
        if (!/^[1-9]\d*$/.test(value)) throw Error('Invalid runtime organization');
        organization = Number(value);
      }
    }
    if (only !== undefined && organization !== undefined) throw Error('Select only a project or an organization');
    const entries = await readRuntimes(only, organization);
    const results = await verifyRuntimes(entries, {requireProbe});
    if (!entries.length) console.log('No registered measurement receivers for selected organization');
    if (results.some(result => !result.ok)) process.exitCode = 1;
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
