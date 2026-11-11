// Each upgrade proof owns a logical clone and its predecessor reconstruction.
// The broad suite may have already committed unrelated synthetic provider facts.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
import {createTestWorkspace} from './runtime_workspace.js';
const root=new URL('../../../',import.meta.url);
export async function withPaymentUpgradeFixture(phase,run){
 assert(['connector','hardening'].includes(phase));
 const source=process.env.DATABASE_URL;assert(source);assertLocalDatabaseUrl(source);
 const admin=new pg.Client({connectionString:source});await admin.connect();
 const workspace=await createTestWorkspace();
 const name=workspace.database;
 const target=new URL(workspace.databaseUrl);target.username='supabase_admin';
 let db;
 try{
  await assertDisposableDatabase(admin);
  db=new pg.Client({connectionString:target.toString()});await db.connect();
  await assertDisposableDatabase(db);
  assert.equal((await db.query('SELECT current_database() name')).rows[0].name,name);
  await db.query("BEGIN; SET LOCAL ROLE postgres; SET LOCAL festapp.email_wake='scheduled'; SET LOCAL request.jwt.claim.role='service_role'; SET LOCAL request.jwt.claim.sub=''");
  // This clone retains reference/configuration rows but creates its own business
  // facts below. No other test's Barion payment may prevent predecessor setup.
  await db.query(`TRUNCATE eshop.payment_info CASCADE;
   DELETE FROM eshop.payment_providers WHERE provider_key='barion';
   DROP TABLE eshop.barion_observations,eshop.barion_sources,eshop.barion_capabilities,eshop.barion_movements,eshop.barion_attempts;
   ALTER TABLE eshop.payment_info DROP COLUMN barion_connection_id;
   DROP TABLE eshop.barion_connections;
   DELETE FROM public.abuse_policy_rules WHERE budget_key='barion.checkout';`);
  if(phase==='connector'){
   const sql=execFileSync('python3',['-c',`import sys
sys.path.insert(0,'automation')
from migration_inputs import read_text
from generate_canonical_source_contract import definitions,statements
frozen=read_text('supabase/migrations/20261106120000_payment_provider_connectors.sql')
hardening=read_text('supabase/migrations/20261106160000_payment_provider_hardening.sql')
previous={}
for statement in statements(frozen):
 for signature,body in definitions(statement):
  if body is not None:previous[signature]=statement
changed={signature for signature,body in definitions(hardening) if body is not None}
for signature in sorted(changed-previous.keys()):print('DROP FUNCTION IF EXISTS '+signature+' CASCADE;')
# Restore all frozen owners, including ones changed by later cash/integration
# migrations. Otherwise this purported predecessor mixes release contracts.
for statement in previous.values():print(statement)
`],{cwd:root,encoding:'utf8',maxBuffer:8*1024*1024});
   await db.query('ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_registered_method, DROP CONSTRAINT payment_info_stripe_connection_identity');
   await db.query(sql);
   assert.equal((await db.query("SELECT to_regprocedure('public.payment_sale_policy_internal()') IS NULL ready")).rows[0].ready,true,'frozen connector predecessor reconstructed');
  }
  await run(db);
 }finally{
  if(db){await db.query('ROLLBACK').catch(()=>{});await db.end();}
  await admin.end();await workspace.release();
 }
}
