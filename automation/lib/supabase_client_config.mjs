#!/usr/bin/env node

import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export function parseSupabaseOrigin(value) {
  const url = new URL(value);
  if (url.protocol !== 'https:' || url.username || url.password ||
      !['', '/'].includes(url.pathname) || url.search || url.hash) {
    throw new Error('Supabase URL must be an HTTPS origin without credentials, path, query, or fragment');
  }
  return url.origin;
}

export function derivedAuthStorageKey(value) {
  const origin = parseSupabaseOrigin(value);
  const host = new URL(origin).hostname;
  const cloudRef = host.match(/^([a-z0-9]+)\.supabase\.co$/)?.[1];
  const namespace = cloudRef ??
    `selfhost-${crypto.createHash('sha256').update(host).digest('hex').slice(0, 16)}`;
  return `sb-${namespace}-auth-token`;
}

export function resolvedAuthStorageKey(value, configuredKey = '') {
  const key = configuredKey || derivedAuthStorageKey(value);
  if (!/^sb-[a-z0-9-]+-auth-token$/.test(key)) {
    throw new Error('Supabase auth storage key must match sb-<namespace>-auth-token');
  }
  return key;
}

function runCli() {
  const [command, value, configuredKey = ''] = process.argv.slice(2);
  if (command === 'origin' && value) {
    process.stdout.write(parseSupabaseOrigin(value));
    return;
  }
  if (command === 'auth-key' && value) {
    process.stdout.write(resolvedAuthStorageKey(value, configuredKey));
    return;
  }
  throw new Error('usage: supabase_client_config.mjs <origin|auth-key> URL [CONFIGURED_KEY]');
}

if (process.argv[1] &&
    fs.realpathSync(path.resolve(process.argv[1])) === fs.realpathSync(fileURLToPath(import.meta.url))) {
  try {
    runCli();
  } catch (error) {
    console.error(`ERROR: ${error.message}`);
    process.exitCode = 1;
  }
}
