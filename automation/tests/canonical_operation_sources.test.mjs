import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
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
  assert.match(read('database/functions/inventory/save_inventory_pool_client_sync_v1.sql'),/public\.save_inventory_pool_command_internal\(p_occasion,p_command_id,p_expected_version,p_bundle,true\)/);
  assert.doesNotMatch(read('database/functions/inventory/update_inventory_pool_bundle_internal_v1.sql'),/save_inventory_pool_client_sync_v1/);
  assert.match(read('database/functions/inventory/save_inventory_pool_command_internal.sql'), /public\.save_inventory_pool_internal\(p_bundle\)/);
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

test('retired implementations have no authored identity or live SQL caller', () => {
  // Parse declarations rather than matching names inside guarded DROP metadata.
  // A retained overload (update_user(jsonb)) is a distinct PostgreSQL identity.
  execFileSync('python3', ['-c', String.raw`
import sys,json,re
from pathlib import Path
sys.path.insert(0,'automation')
from generate_canonical_source_contract import statements,CREATE,identity
retired=set(json.loads(Path('automation/canonical-source-contract.json').read_text())['retiredSignatures'])
functions=[]
for path in Path('database/functions').rglob('*.sql'):
 for statement in statements(path.read_text()):
  if match:=CREATE.search(statement):
   signature=identity(match[1],match[2],True)
   assert signature not in retired,(str(path),signature)
   functions.append((signature,match[5],str(path)))
active_names={sig.split('(')[0] for sig,_,_ in functions}
retired_names={sig.split('(')[0] for sig in retired}-active_names
for signature,body,path in functions:
 body=re.sub(r"--[^\n]*|/\*.*?\*/|'(?:''|[^'])*'",'',body,flags=re.S)
 for name in retired_names:
  assert not re.search(r'\b'+re.escape(name.removeprefix('public.'))+r'\s*\(',body,re.I),(path,signature,name)
`], {stdio:'pipe'});
});

 test('ticket batch ACL restoration uses the canonical access owner', () => {
  const access = read('database/functions/eshop_ticket_batches/access.sql');
  const migration = read('supabase/migrations/20261106143000_restore_ticket_batch_client_access.sql');
  assert.equal(migration.slice(migration.indexOf('-- Apply after')), access);
 });

test('payment lifecycle retains recovery history and provider-aware reconciliation', () => {
  const recovery = read('database/functions/eshop_waitlist/fakturoid_recovery.sql');
  const historical = read('supabase/migrations/20261106144000_restore_payment_email_lifecycle.sql');
  assert.ok(historical.endsWith(recovery));
  execFileSync('python3', ['automation/assemble-payment-provider-integration-migration.py', '--check']);
  execFileSync('python3', ['automation/assemble-payment-provider-hardening-migration.py', '--check']);
});

test('installed payment integration cannot be rewritten and rejects changed historical bytes', () => {
  const config = JSON.parse(read('automation/payment-provider-integration-migration.json'));
  const target = `supabase/migrations/${config.migration}`;
  const original = read(target);
  const write = spawnSync('python3',['automation/assemble-payment-provider-integration-migration.py'],{encoding:'utf8'});
  assert.notEqual(write.status,0);
  assert.match(write.stderr,/immutable/);
  assert.equal(read(target),original);
  const root=fs.mkdtempSync(path.join(os.tmpdir(),'payment-history-guard-'));
  try {
    fs.mkdirSync(path.join(root,'automation'),{recursive:true});
    fs.mkdirSync(path.join(root,'supabase/migrations'),{recursive:true});
    fs.writeFileSync(path.join(root,'automation/payment-provider-integration-migration.json'),JSON.stringify(config));
    fs.writeFileSync(path.join(root,target),original+'\n-- changed history\n');
    const result=spawnSync('python3',['-c',
      "import sys,importlib.util; from pathlib import Path; sys.path.insert(0,'automation'); spec=importlib.util.spec_from_file_location('integration','automation/assemble-payment-provider-integration-migration.py'); module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module); module.render(Path(sys.argv[1]))",root],{encoding:'utf8'});
    assert.notEqual(result.status,0);
    assert.match(result.stderr,/Installed payment integration migration bytes changed/);
  } finally { fs.rmSync(root,{recursive:true,force:true}); }
});
