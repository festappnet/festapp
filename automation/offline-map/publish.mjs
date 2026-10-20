#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';

const CACHE_CONTROL = 'public, max-age=31536000, immutable';
const PUBLIC_ORIGIN = 'https://assets.festapp.net';
const BUCKET = 'festapp-public';
const CONCURRENCY = 4;

function fail(message) {
  throw new Error(message);
}

function sha256(buffer) {
  return crypto.createHash('sha256').update(buffer).digest('hex');
}

async function run(command, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(command, args, { stdio: ['ignore', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.once('error', reject);
    child.once('close', code => {
      if (code === 0) resolve(stdout);
      else reject(new Error(`${command} exited ${code}: ${stderr.slice(-2000)}`));
    });
  });
}

async function pooled(items, action) {
  let cursor = 0;
  const workers = Array.from({ length: Math.min(CONCURRENCY, items.length) }, async () => {
    while (cursor < items.length) {
      const item = items[cursor++];
      await action(item);
    }
  });
  await Promise.all(workers);
}

async function fetchWithRetry(url, options = {}) {
  let response;
  for (let attempt = 0; attempt < 5; attempt += 1) {
    response = await fetch(url, { redirect: 'error', ...options });
    if (response.status !== 404 || attempt === 4) return response;
    await new Promise(resolve => setTimeout(resolve, 1000 * (attempt + 1)));
  }
  return response;
}

async function main() {
  const args = process.argv.slice(2);
  const verifyOnly = args[0] === '--verify-only';
  if (verifyOnly) args.shift();
  const [manifestArg, bundleArg] = args;
  if (!manifestArg || !bundleArg) {
    fail('usage: publish.mjs [--verify-only] MANIFEST.json BUNDLE_DIRECTORY');
  }

  const manifestPath = path.resolve(manifestArg);
  const bundleDir = path.resolve(bundleArg);
  const manifestBytes = fs.readFileSync(manifestPath);
  const manifest = JSON.parse(manifestBytes);
  const baseUrl = new URL(manifest.base_url);
  if (baseUrl.origin !== PUBLIC_ORIGIN || !baseUrl.pathname.endsWith('/') ||
      !Array.isArray(manifest.assets) || manifest.assets.length === 0) {
    fail('manifest does not target the approved immutable public asset namespace');
  }

  const entries = manifest.assets.map(asset => {
    const url = new URL(asset.url);
    if (url.origin !== PUBLIC_ORIGIN || !url.pathname.startsWith(baseUrl.pathname) ||
        path.posix.normalize(asset.path) !== asset.path || asset.path.startsWith('../')) {
      fail(`unsafe asset path or URL: ${asset.path}`);
    }
    const file = path.resolve(bundleDir, asset.path);
    if (!file.startsWith(`${bundleDir}${path.sep}`)) fail(`asset escapes bundle: ${asset.path}`);
    const bytes = fs.readFileSync(file);
    if (bytes.length !== asset.bytes || sha256(bytes) !== asset.sha256) {
      fail(`local asset does not match manifest: ${asset.path}`);
    }
    return { ...asset, file, url: url.href, key: url.pathname.slice(1) };
  });
  const manifestUrl = new URL('manifest.json', baseUrl);
  const manifestEntry = {
    path: 'manifest.json',
    file: manifestPath,
    url: manifestUrl.href,
    key: manifestUrl.pathname.slice(1),
    content_type: 'application/json',
    bytes: manifestBytes.length,
    sha256: sha256(manifestBytes),
  };

  if (!verifyOnly) {
    // A unique query prevents negative CDN lookups from poisoning canonical URLs.
    const preflight = crypto.randomUUID();
    await pooled([...entries, manifestEntry], async entry => {
      const url = new URL(entry.url);
      url.searchParams.set('festapp-r2-preflight', preflight);
      const response = await fetch(url, { method: 'HEAD', redirect: 'error' });
      if (response.status !== 404) fail(`immutable target already exists (${response.status}): ${entry.url}`);
    });

    await pooled(entries, async entry => {
      await run('npx', ['--yes', 'wrangler@latest', 'r2', 'object', 'put',
        `${BUCKET}/${entry.key}`, '--remote', '--file', entry.file,
        '--content-type', entry.content_type, '--cache-control', CACHE_CONTROL]);
    });
    // The manifest is the publication marker and is intentionally uploaded last.
    await run('npx', ['--yes', 'wrangler@latest', 'r2', 'object', 'put',
      `${BUCKET}/${manifestEntry.key}`, '--remote', '--file', manifestEntry.file,
      '--content-type', manifestEntry.content_type, '--cache-control', CACHE_CONTROL]);
  }

  await pooled([...entries, manifestEntry], async entry => {
    const response = await fetchWithRetry(entry.url);
    if (!response.ok) fail(`public GET failed (${response.status}): ${entry.url}`);
    const contentType = response.headers.get('content-type')?.split(';')[0];
    const cacheControl = response.headers.get('cache-control');
    const bytes = Buffer.from(await response.arrayBuffer());
    if (contentType !== entry.content_type || cacheControl !== CACHE_CONTROL ||
        bytes.length !== entry.bytes || sha256(bytes) !== entry.sha256) {
      fail(`public asset verification mismatch: ${entry.url}`);
    }
  });

  process.stdout.write(JSON.stringify({
    mode: verifyOnly ? 'verify-only' : 'publish',
    published: verifyOnly ? 0 : entries.length + 1,
    assets: entries.length,
    manifest_url: manifestEntry.url,
    manifest_sha256: manifestEntry.sha256,
    deleted_objects: 0,
  }) + '\n');
}

main().catch(error => {
  process.stderr.write(`ERROR: ${error.message}\n`);
  process.exitCode = 1;
});
