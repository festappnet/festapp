import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';
const read = p => fs.readFileSync(p, 'utf8');
const manifest = JSON.parse(read('automation/canonical-operation-sources.json'));
function files(dir) {
  return fs.readdirSync(dir, {withFileTypes:true}).flatMap(e => e.isDirectory()
    ? files(path.join(dir,e.name)) : e.name.endsWith('.sql') ? [path.join(dir,e.name)] : []);
}
test('one authored owner per selected PostgreSQL function identity', () => {
  const sourceText=new Map(files('database/functions').map(p=>[p,read(p)]));
  const owners=manifest.sources.flatMap(owner=>[...sourceText.get(`database/functions/${owner}`).matchAll(
    /CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+(?:public\.)?(\w+)\s*\(/ig)]
    .map(m=>[m[1],owner]));
  for (const [name,owner] of owners) {
    const declarations = p => [...sourceText.get(p).matchAll(new RegExp(
      `CREATE\\s+(?:OR\\s+REPLACE\\s+)?FUNCTION\\s+(?:public\\.)?${name}\\s*\\(([\\s\\S]*?)\\)\\s*RETURNS\\b`, 'ig'))]
      .map(m => m[1].split(',').map(arg => arg.replace(/\bDEFAULT\b[\s\S]*/i,'').trim().split(/\s+/).slice(1).join(' ').toLowerCase()).join(','));
    const selected = declarations(`database/functions/${owner}`);
    assert.ok(selected.length,name);
    for (const signature of selected) {
      const definitions=files('database/functions').flatMap(p => declarations(p).filter(sig=>sig===signature).map(()=>p));
      assert.deepEqual(definitions,[`database/functions/${owner}`],`${name}(${signature})`);
    }
  }
});
test('forward manifest is deterministic, definition-only and refuses historical targets', () => {
  execFileSync('python3',['automation/assemble-operations-foundation-migration.py','--check']);
  assert.equal(new Set(manifest.sources).size,manifest.sources.length);
  const sql = read('supabase/migrations/20261020120000_canonical_operations_foundation.sql');
  assert.doesNotMatch(sql,/INSERT INTO public\.abuse_budget_usage|DROP TABLE public\.(password_reset|external_login)_rate_limits/);
  const rejected = spawnSync('python3',['automation/assemble-operations-foundation-migration.py','--output','supabase/migrations/20261016100000_abuse_admission.sql']);
  assert.notEqual(rejected.status,0);
  assert.doesNotMatch(read('automation/assemble-abuse-migration.py'), /\.write_text\(/);
  assert.doesNotMatch(read('automation/assemble-operations-foundation-migration.py'), /\.write_text\(/);
  const installedWrite = spawnSync('python3',['automation/assemble-operations-foundation-migration.py','--output','supabase/migrations/20261020120000_canonical_operations_foundation.sql']);
  assert.notEqual(installedWrite.status,0);
});
test('current order callers reach the command and have no automatic email follow-up', () => {
  const source=read('lib/components/eshop/db_orders.dart');
  assert.doesNotMatch(source,/update_order_and_tickets_to_storno_ws_221|delete_order_221/);
  const cancellation=source.split('static Future<void> stornoOrder(')[1].split('static Future<SpotSelectionResult>')[0];
  assert.doesNotMatch(cancellation,/sendStornoTicketOrderEmail|functions\.invoke/);
  const followup=read('lib/components/eshop/ticket_cancellation_updates.dart');
  assert.match(followup,/if \(!send \|\| !context\.mounted\) continue/);
  assert.match(followup,/DbOrders\.sendStornoTicketOrderEmail/);
  assert.doesNotMatch(read('database/functions/eshop_orders/storno_tickets_bulk.sql'),/enqueue_order_email/);
  assert.match(read('database/functions/eshop_orders/delete_order_client_sync_v1.sql'),/r\.actor_id=v_actor AND r\.request_sha256=v_hash/);
});
test('pool and cleaning facade graphs terminate in private owners without recursion', () => {
  assert.match(read('database/functions/inventory/save_inventory_pool_client_sync_v1.sql'),/public\.update_inventory_pool_bundle_internal_v1\(p_bundle\)/);
  assert.doesNotMatch(read('database/functions/inventory/update_inventory_pool_bundle_internal_v1.sql'),/save_inventory_pool_client_sync_v1/);
  assert.match(read('database/functions/cleaning/report_cleaning_issue_client_sync_v1.sql'),/public\.report_cleaning_issue_internal_v1\(/);
  const report=read('database/functions/cleaning/report_cleaning_issue.sql');
  assert.doesNotMatch(report.split('CREATE OR REPLACE FUNCTION public.report_cleaning_issue(place_id')[0],/report_cleaning_issue_client_sync_v1\(/);
  for(const p of ['lib/components/groups/db_groups.dart','lib/components/inventory/db_inventory_pools.dart','lib/components/cleaning/db_cleaning.dart','lib/components/forms/db_forms.dart']) {
    assert.doesNotMatch(read(p),/updateUserGroupParticipants|updateLegacyPrivateGroupPlace|deleteLegacyPrivateGroupPlace/);
  }
});
test('activity publication no longer performs broad post-publish autosave deletion', () => {
  const content=read('lib/components/activities/activities_content.dart');
  const published=content.split('await DbActivities.saveActivitiesForEdit(')[1].split('_isAutosaveLoaded = false')[0];
  assert.doesNotMatch(published,/deleteAutosave/);
  assert.match(read('database/functions/activities/canonical_activity_history.sql'),/h\.id=\(p_selection->>'id'\)::bigint/);
  assert.match(read('database/functions/activities/canonical_activity_lifecycle.sql'),/consume_selected_activity_draft_internal_v1/);
});
test('all forward SECURITY DEFINER owners pin the trusted search path', () => {
  for (const source of manifest.sources) {
    const sql = read(`database/functions/${source}`);
    for (const match of sql.matchAll(/CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([\w.]+)\s*\([\s\S]*?\bAS\s+\$\w*\$/ig)) {
      if (!/SECURITY\s+DEFINER/i.test(match[0])) continue;
      assert.match(match[0], /SET\s+search_path\s*(?:=|TO)\s*'?public'?\s*,\s*'?extensions'?/i, `${source}: ${match[1]}`);
    }
  }
});

test('effective SQL source fingerprints are reproducible from release inputs', () => {
  execFileSync('python3',['automation/generate_canonical_source_contract.py','--check']);
  execFileSync('python3',['automation/generate_ticket_layout_write_contract.py','--check']);
  execFileSync('python3',['-m','unittest','discover','-s','automation/tests','-p','test_canonical_source_contract.py']);
});

test('retired profile implementations have no authored definition or SQL caller', () => {
  const retired = JSON.parse(read('automation/canonical-source-contract.json')).retiredSignatures;
  const sql = files('database/functions').map(read).join('\n');
  for (const signature of retired) {
    const name = signature.split('(')[0].split('.').at(-1);
    assert.doesNotMatch(sql, new RegExp(`\\b${name}\\s*\\(`, 'i'), signature);
  }
});
