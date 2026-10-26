#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import {
  backendActivationDocument,
  canonicalBackendActivationSha256,
} from '../lib/backend_activation_manifest.mjs';

const [tenantId = '', phase = '', ...outputs] = process.argv.slice(2);
if (outputs.length === 0) {
  throw new Error('usage: generate_backend_activation_manifest.mjs TENANT PHASE OUTPUT...');
}

if (!tenantId) {
  for (const output of outputs) fs.rmSync(output, { force: true });
  process.stdout.write('disabled');
} else {
  const document = backendActivationDocument(tenantId, phase);
  for (const output of outputs) {
    fs.mkdirSync(path.dirname(output), { recursive: true });
    fs.writeFileSync(output, document, { mode: 0o644 });
  }
  process.stdout.write(canonicalBackendActivationSha256(tenantId));
}
