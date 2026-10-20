import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { buildInventory, extractCalls, renderInventory } from '../generate_operation_inventory.mjs';

test('collects actual literal calls without treating comments or declarations as calls', () => {
  const source = `// client.rpc('commented_out');
    /* client.functions.invoke('obsolete-edge'); */
    client.rpc('read_order', {});
    client.functions.invoke('send-ticket-order', {});
    _invoke('save_order', {});
    Future<void> _invoke(String name, Map params) {}
    _legacyRpc!('old_order', {});
  `;
  const { found, dynamic } = extractCalls(source, 'lib/example.dart');
  assert.deepEqual(found.map(x => [x.kind, x.name]), [
    ['rpc', 'read_order'], ['edge', 'send-ticket-order'], ['rpc', 'save_order'], ['rpc', 'old_order'],
  ]);
  assert.equal(dynamic.length, 0);
});

test('collects generic Worker RPCs and HTTP path references without recording URL credentials', () => {
  const { found } = extractCalls(`
    this.rpc<DirtyKey[]>('claim_dirty', {});
    fetch(\`\${origin}/rest/v1/rpc/check_upload_permission\`);
  `, 'workers/example/src/client.ts');
  assert.deepEqual(found.map(x => x.name), ['claim_dirty', 'check_upload_permission']);
  assert.equal(found[1].via, 'http-path-reference');
  assert.ok(!JSON.stringify(found).includes('origin'));
});

test('keeps unresolved calls explicit and labels finite selector candidates', () => {
  const { found, dynamic } = extractCalls(`
    const rpcName = replacement ? 'replace_order' : 'create_order';
    client.rpc(rpcName, {});
    client.rpc(useNew ? 'new_reader' : 'old_reader', {});
    client.rpc(externalName, {});
  `, 'supabase/functions/example/index.ts');
  assert.deepEqual(found.map(x => x.name), ['replace_order', 'create_order', 'new_reader', 'old_reader']);
  assert.equal(dynamic.length, 3);
  assert.equal(found[0].via, 'local-selector-candidate');
});

test('includes forwarded scanner calls and Tb table candidates without claiming write behavior', () => {
  const { found } = extractCalls(`this.call('lookup_scanner_ticket', {});
    client.from(Tb.images.table).select();`, 'web_client/src/services/scanner_api.js');
  assert.deepEqual(found.map(x => [x.kind, x.name]), [['rpc', 'lookup_scanner_ticket'], ['table-candidate', 'images']]);
});

test('inventory preserves authored duplicates, migration-only evidence and policy-only surfaces deterministically', () => {
  const fixture = fs.mkdtempSync(path.join(os.tmpdir(), 'festapp-operation-inventory-'));
  const write = (relative, value) => {
    const target = path.join(fixture, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, value);
  };
  try {
    write('automation/hetzner-supabase/merge/runtime-writer-policy.json', JSON.stringify({ edge_functions: {
      'provider-event': { trigger: 'callback', effects: ['database-rpc'] },
    } }));
    write('lib/client.dart', "client.rpc('authored'); client.rpc('migration_only');");
    write('lib/tests/ignored.dart', "client.rpc('test_only');");
    write('database/functions/one.sql', 'CREATE OR REPLACE FUNCTION public.authored(p_id bigint) RETURNS jsonb LANGUAGE sql AS $$ SELECT NULL $$;');
    write('database/functions/two.sql', 'CREATE OR REPLACE FUNCTION public.authored(p_id bigint) RETURNS jsonb LANGUAGE sql AS $$ SELECT NULL $$;');
    write('supabase/migrations/20260101.sql', 'CREATE FUNCTION public.migration_only() RETURNS void LANGUAGE sql AS $$ SELECT NULL $$;');
    write('supabase/functions/source-only/index.ts', 'export const marker = true;');
    const inventory = buildInventory(fixture);
    assert.equal(inventory.rpc.length, 2);
    assert.equal(inventory.rpc[0].definitions.length, 2);
    assert.equal(inventory.rpc[1].definitions.length, 0);
    assert.equal(inventory.rpc[1].migrationReference.file, 'supabase/migrations/20260101.sql');
    assert.equal(inventory.edge.find(x => x.name === 'source-only').policyStatus, 'source-only-not-in-policy');
    assert.equal(inventory.edge.find(x => x.name === 'provider-event').references.length, 0);
    assert.deepEqual(buildInventory(fixture), inventory);
    assert.match(renderInventory(inventory), /migration only/);
  } finally {
    fs.rmSync(fixture, { recursive: true, force: true });
  }
});
