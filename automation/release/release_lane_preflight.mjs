#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');

export function parseProjectConfig(source) {
  const entries = {};
  for (const rawLine of source.split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const separator = line.indexOf('=');
    if (separator < 1) continue;
    const key = line.slice(0, separator).trim();
    let value = line.slice(separator + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) value = value.slice(1, -1);
    entries[key] = value;
  }
  return entries;
}

export function releaseLaneContractErrors({ manifest, config, manifestPath, mode, repoRoot }) {
  const errors = [];
  const fail = (message) => errors.push(message);
  const activationTenant = config.BACKEND_ACTIVATION_TENANT_ID;
  const expectedBranch = activationTenant ? `prod/${activationTenant}` : '';

  if (!['web', 'mobile'].includes(mode)) fail('mode must be web or mobile');
  if (manifest.schemaVersion !== 2) {
    fail('the canonical web/mobile release manifest must use schemaVersion 2');
  }
  if (!manifest.backend) fail('release manifest is missing its backend contract');
  if (!activationTenant) fail('project.conf is missing BACKEND_ACTIVATION_TENANT_ID');
  if (manifest.backend?.activation?.tenantId !== activationTenant) {
    fail('release manifest activation tenant disagrees with project.conf');
  }
  if (manifest.backend?.releaseIntent !== 'canonical-cutover') {
    fail('release manifest must declare backend.releaseIntent=canonical-cutover');
  }
  if (!manifestPath || !path.isAbsolute(manifestPath)) {
    fail('FESTAPP_RELEASE_MANIFEST must resolve to an absolute path');
  } else {
    const relative = path.relative(repoRoot, manifestPath);
    if (relative !== '..' && !relative.startsWith(`..${path.sep}`) && !path.isAbsolute(relative)) {
      fail('tenant publishing manifests must remain outside the public Festapp repository');
    }
  }

  if (mode === 'mobile') {
    if (!manifest.bundleId || manifest.bundleId !== config.IOS_BUNDLE_ID) {
      fail('release manifest bundleId disagrees with project.conf IOS_BUNDLE_ID');
    }
    if (!manifest.androidPackage || manifest.androidPackage !== config.ANDROID_APPLICATION_ID) {
      fail('release manifest androidPackage disagrees with project.conf ANDROID_APPLICATION_ID');
    }
    if (!manifest.releaseBranch || manifest.releaseBranch !== expectedBranch) {
      fail(`release manifest releaseBranch must be ${expectedBranch || 'the configured production branch'}`);
    }
  }
  return errors;
}

function run(script, args) {
  const result = spawnSync(process.execPath, [path.join(root, script), ...args], {
    cwd: root,
    env: process.env,
    encoding: 'utf8',
  });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) process.exit(result.status ?? 1);
}

function main() {
  const modeArgs = process.argv.slice(2).filter((arg) => arg === '--web' || arg === '--mobile');
  if (modeArgs.length !== 1 || process.argv.length !== 3) {
    console.error('Usage: release_lane_preflight.mjs <--web|--mobile>');
    process.exit(1);
  }
  const mode = modeArgs[0].slice(2);
  const manifestValue = process.env.FESTAPP_RELEASE_MANIFEST?.trim();
  if (!manifestValue) {
    console.error('ERROR: Set FESTAPP_RELEASE_MANIFEST to the canonical private schema-2 manifest.');
    process.exit(1);
  }
  const requestedManifestPath = path.resolve(manifestValue);
  if (!fs.existsSync(requestedManifestPath)) {
    console.error(`ERROR: missing release manifest ${requestedManifestPath}`);
    process.exit(1);
  }
  const manifestPath = fs.realpathSync(requestedManifestPath);
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const config = parseProjectConfig(fs.readFileSync(path.join(root, 'automation/project.conf'), 'utf8'));
  const errors = releaseLaneContractErrors({ manifest, config, manifestPath, mode, repoRoot: root });
  if (errors.length) {
    for (const error of errors) console.error(`ERROR: ${error}`);
    process.exit(1);
  }

  run('automation/release/client_cutover_preflight.mjs', ['--require-canonical-cutover']);
  if (mode === 'mobile') {
    run('automation/release/store_preflight.mjs', ['--local', '--read-only']);
  }
  console.log(`Canonical ${mode} release-lane preflight passed.`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) main();
