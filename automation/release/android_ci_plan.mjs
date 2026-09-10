#!/usr/bin/env node

import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const tenantPattern = /^[a-z0-9][a-z0-9-]{1,62}$/;
const shaPattern = /^[0-9a-f]{40}$/;
const hashPattern = /^[0-9a-f]{64}$/;
const packagePattern = /^[A-Za-z][A-Za-z0-9_]*(?:\.[A-Za-z][A-Za-z0-9_]*)+$/;

export function normalizeCandidateTargets(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 30) {
    throw new Error('targets_json must contain between 1 and 30 tenant names');
  }
  const seen = new Set();
  return value.map((tenant) => {
    if (typeof tenant !== 'string' || !tenantPattern.test(tenant)) {
      throw new Error(`invalid tenant name: ${String(tenant)}`);
    }
    if (seen.has(tenant)) throw new Error(`duplicate tenant: ${tenant}`);
    seen.add(tenant);
    return { tenant, branch: `prod/${tenant}` };
  });
}

export function normalizeProductionTargets(value) {
  if (!Array.isArray(value) || value.length < 1 || value.length > 30) {
    throw new Error('releases_json must contain between 1 and 30 releases');
  }
  const seen = new Set();
  return value.map((release) => {
    const tenant = release?.tenant;
    const packageName = release?.packageName;
    const versionCode = Number(release?.versionCode);
    const sourceSha = release?.sourceSha?.toLowerCase();
    const artifactSha256 = release?.artifactSha256?.toLowerCase();
    if (typeof tenant !== 'string' || !tenantPattern.test(tenant)) throw new Error('invalid tenant');
    if (typeof packageName !== 'string' || !packagePattern.test(packageName)) throw new Error(`invalid package for ${tenant}`);
    if (!Number.isSafeInteger(versionCode) || versionCode < 1) throw new Error(`invalid versionCode for ${tenant}`);
    if (!shaPattern.test(sourceSha ?? '')) throw new Error(`invalid sourceSha for ${tenant}`);
    if (!hashPattern.test(artifactSha256 ?? '')) throw new Error(`invalid artifactSha256 for ${tenant}`);
    if (release?.action !== 'production-completed') throw new Error(`invalid action for ${tenant}`);
    if (seen.has(packageName)) throw new Error(`duplicate package: ${packageName}`);
    seen.add(packageName);
    return {
      tenant,
      branch: `prod/${tenant}`,
      packageName,
      versionCode,
      sourceSha,
      artifactSha256,
      action: 'production-completed',
    };
  });
}

function remoteHead(branch) {
  const output = execFileSync('git', ['ls-remote', '--heads', 'origin', `refs/heads/${branch}`], {
    cwd: root,
    encoding: 'utf8',
  }).trim();
  const [sha, ref, extra] = output.split(/\s+/);
  if (!shaPattern.test(sha ?? '') || ref !== `refs/heads/${branch}` || extra) {
    throw new Error(`cannot resolve one exact remote head for ${branch}`);
  }
  return sha;
}

function main() {
  const [mode, inputPath] = process.argv.slice(2);
  if (!['candidate', 'production'].includes(mode) || !inputPath) {
    console.error('Usage: android_ci_plan.mjs <candidate|production> <json-file>');
    process.exit(2);
  }
  const input = JSON.parse(fs.readFileSync(path.resolve(inputPath), 'utf8'));
  const targets = mode === 'candidate'
    ? normalizeCandidateTargets(input).map((target) => ({ ...target, sourceSha: remoteHead(target.branch) }))
    : normalizeProductionTargets(input);
  if (mode === 'production') {
    for (const target of targets) {
      if (remoteHead(target.branch) !== target.sourceSha) {
        throw new Error(`${target.branch} advanced after candidate ${target.sourceSha}`);
      }
    }
  }
  process.stdout.write(JSON.stringify({ include: targets }));
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try { main(); } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exit(1);
  }
}
