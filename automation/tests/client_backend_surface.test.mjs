#!/usr/bin/env node

import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import {
  extractClientEdgeContract,
  extractClientRelationContract,
} from '../release/audit_client_backend_surface.mjs';

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-backend-surface-'));
try {
  fs.mkdirSync(path.join(fixture, 'lib/database_tables'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'lib/components/eshop/models'), { recursive: true });
  fs.mkdirSync(path.join(fixture, 'web_client/src'), { recursive: true });
  fs.writeFileSync(path.join(fixture, 'lib/client.dart'), `
    client.functions.invoke('send-email', body: const {});
    client.functions.invoke("download-ticket", body: const {});
    print(Tb.events.table);
    print(TbEshop.orders.table);
  `);
  fs.writeFileSync(path.join(fixture, 'web_client/src/client.js'), `
    client.functions.invoke('register', { body: {} });
    client.from('literal_table').select();
  `);
  fs.writeFileSync(path.join(fixture, 'lib/database_tables/tb.dart'), `
    class Tb { static PublicTable events = const PublicTable(); }
    class PublicTable { const PublicTable(); String get table => "events"; }
  `);
  fs.writeFileSync(path.join(fixture, 'lib/components/eshop/models/tb_eshop.dart'), `
    class TbEshop { static EshopTable orders = const EshopTable(); }
    class EshopTable { const EshopTable(); String get table => 'orders'; }
  `);
  assert.deepEqual(extractClientEdgeContract(fixture).map(({ name }) => name),
    ['download-ticket', 'register', 'send-email']);
  assert.deepEqual(extractClientRelationContract(fixture).map(({ name }) => name),
    ['eshop.orders', 'public.events', 'public.literal_table']);
  console.log('Client backend surface extraction passed.');
} finally {
  fs.rmSync(fixture, { recursive: true, force: true });
}
