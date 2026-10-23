#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { extractClientRpcContract } from '../release/audit_client_rpc_contract.mjs';

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-rpc-contract-'));
try {
  fs.mkdirSync(path.join(fixture, 'lib'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'web_client/src'), { recursive: true });
  fs.writeFileSync(path.join(fixture, 'lib/client.dart'), `
    client.rpc('direct_rpc', params: const {});
    _transport.invoke("command_rpc", const {});
    _invoke('wrapped_rpc', const {});
    _configurationCommand('configuration_rpc', const {});
    _adminCommand('admin_rpc', 1, 2);
    _readRpc('preview_rpc', {});
    invoke('callback_rpc');
    client.functions.invoke('edge-function');
  `);
  fs.writeFileSync(path.join(fixture, 'web_client/src/client.js'), `
    client.rpc('web_rpc', {});
  `);
  assert.deepEqual(
    extractClientRpcContract(fixture).map((entry) => entry.name),
    ['admin_rpc', 'callback_rpc', 'command_rpc', 'configuration_rpc', 'direct_rpc', 'preview_rpc', 'web_rpc', 'wrapped_rpc'],
  );
  console.log('Client RPC contract extraction passed.');
} finally {
  fs.rmSync(fixture, { recursive: true, force: true });
}
