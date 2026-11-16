#!/usr/bin/env node
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import { createHash } from 'node:crypto';
import { walletPresentation } from '../supabase/functions/_shared/wallet/presentation.js';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

export function imageClientConfig(source) {
  const value = (key) => source.match(new RegExp(`^${key}=(.*)$`, 'm'))?.[1]
    .trim().replace(/^(['"])(.*)\1$/, '$2') ?? '';
  const origin = new URL(value('WEB_LINK')).origin;
  const endpoint = value('IMAGE_API_URL').replace(/\/$/, '');
  const project = value('IMAGE_PROJECT_ID');
  if (!origin.startsWith('https://') || !endpoint.startsWith('https://') || !project) {
    throw new Error('Image client requires HTTPS WEB_LINK, IMAGE_API_URL and IMAGE_PROJECT_ID');
  }
  return { tenant: value('BACKEND_ACTIVATION_TENANT_ID'), origin, endpoint, project };
}

export async function verifyImageClient(client, request = fetch) {
  const preflight = await request(`${client.endpoint}/upload`, {
    method: 'OPTIONS',
    headers: {
      Origin: client.origin,
      'Access-Control-Request-Method': 'POST',
      'Access-Control-Request-Headers': 'authorization,content-type',
    },
    signal: AbortSignal.timeout(15000),
  });
  const methods = (preflight.headers.get('access-control-allow-methods') ?? '').split(',').map(v => v.trim());
  const headers = (preflight.headers.get('access-control-allow-headers') ?? '').toLowerCase().split(',').map(v => v.trim());
  if (preflight.status !== 204 || preflight.headers.get('access-control-allow-origin') !== client.origin ||
      !methods.includes('POST') || !headers.includes('authorization') || !headers.includes('content-type')) {
    throw new Error(`${client.tenant}: upload preflight rejected or incomplete (HTTP ${preflight.status})`);
  }
  // This deliberately invalid token cannot authorize an object or database write.
  // Project resolution precedes permission validation in the real upload handler.
  const body = new FormData();
  body.set('projectId', client.project);
  body.set('occasionId', '1');
  body.set('file', new Blob([], { type: 'image/png' }), 'diagnostic.png');
  const response = await request(`${client.endpoint}/upload`, {
    method: 'POST',
    headers: { Origin: client.origin, Authorization: 'Bearer diagnostic-invalid-token' },
    body,
    signal: AbortSignal.timeout(15000),
  });
  const result = await response.json();
  if (response.status !== 403 || result.error?.code !== 'FORBIDDEN' ||
      response.headers.get('access-control-allow-origin') !== client.origin) {
    throw new Error(`${client.tenant}: image project ${client.project} failed authorization boundary (${result.error?.code ?? response.status})`);
  }
  return client;
}

// Email clients load these immutable public objects independently of the web build.
export async function verifyWalletEmailArtwork(request = fetch) {
  const assets = ['apple', 'google'].flatMap(provider =>
    Object.entries(walletPresentation[provider].emailBadges).map(([locale, url]) => ({
      url,
      file: path.join(root, 'assets/brand', `${provider}-wallet`, provider === 'apple' ? 'email' : 'condensed', `${locale}.png`),
    })));
  await Promise.all(assets.map(async ({ url, file }) => {
    const response = await request(url, { signal: AbortSignal.timeout(15000) });
    if (!response.ok || response.headers.get('content-type')?.split(';')[0] !== 'image/png') {
      throw new Error(`Wallet email artwork unavailable: ${url} (HTTP ${response.status})`);
    }
    const digest = bytes => createHash('sha256').update(bytes).digest('hex');
    if (digest(Buffer.from(await response.arrayBuffer())) !== digest(fs.readFileSync(file))) {
      throw new Error(`Wallet email artwork differs from canonical file: ${url}`);
    }
  }));
  return assets.length;
}

async function main() {
  const args = process.argv.slice(2);
  let sources;
  if (args.length === 1 && args[0] === '--all-tenants') {
    const tenants = JSON.parse(fs.readFileSync(path.join(root, 'automation/tenant-overlays/tenant-overlay.schema.json'), 'utf8'))
      .properties.tenantId.enum;
    sources = tenants.map(tenant => execFileSync('git', ['show', `origin/prod/${tenant}:automation/project.conf`], {
      cwd: root, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
    }));
  } else if (args.length === 0 || (args.length === 2 && args[0] === '--config')) {
    sources = [fs.readFileSync(args[1] ?? path.join(root, 'automation/project.conf'), 'utf8')];
  } else {
    throw new Error('Usage: verify_image_service.mjs [--config PATH | --all-tenants]');
  }
  const results = await Promise.allSettled(sources.map(source => verifyImageClient(imageClientConfig(source))));
  const failures = results.filter(result => result.status === 'rejected');
  if (failures.length) throw new Error(failures.map(result => result.reason.message).join('\n'));
  await verifyWalletEmailArtwork();
  console.log(`Image service: ${results.length} client configuration(s) passed CORS and project checks`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(error => { console.error(error.message); process.exitCode = 1; });
}
