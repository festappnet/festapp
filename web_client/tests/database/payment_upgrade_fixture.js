// Each upgrade proof owns a logical clone and its predecessor reconstruction.
// The broad suite may have already committed unrelated synthetic provider facts.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {mkdtemp,readFile,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {randomUUID} from 'node:crypto';
import pg from 'pg';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from './disposable_database.js';
const root=new URL('../../../',import.meta.url);
export async function withPaymentUpgradeFixture(phase,run){
 assert(['connector','hardening'].includes(phase));
 const source=process.env.DATABASE_URL;assert(source);assertLocalDatabaseUrl(source);
 const admin=new pg.Client({connectionString:source});await admin.connect();
 const name='festapp_payment_upgrade_'+randomUUID().replaceAll('-','');
 const target=new URL(source);target.pathname='/'+name;target.username='supabase_admin';
 const kit=await mkdtemp(tmpdir()+'/festapp-payment-upgrade-');let db,created=false;
 try{
  await assertDisposableDatabase(admin);
  execFileSync('pg_dump',[source,'--no-owner','--exclude-schema=cron','--exclude-schema=net','--file',kit+'/snapshot.sql'],{stdio:'pipe'});
  const dump=(await readFile(kit+'/snapshot.sql','utf8'))
   .replace(/^SET transaction_timeout = 0;$/m,'')
   .replace(/^CREATE EXTENSION IF NOT EXISTS (pg_cron|pg_net)\b[^;]*;$/gm,'')
   .replace(/^COMMENT ON EXTENSION (pg_cron|pg_net)\b[^;]*;$/gm,'')
   .replace(/^(?:ALTER DEFAULT PRIVILEGES|GRANT|REVOKE).*\b(?:cron|net|graphql_public)\b.*$/gm,'');
  await writeFile(kit+'/snapshot.sql',dump);
  await admin.query(`CREATE DATABASE ${name} TEMPLATE template0`);created=true;
  db=new pg.Client({connectionString:target.toString()});await db.connect();
  await db.query('CREATE SCHEMA cron; CREATE SCHEMA net');
  execFileSync('psql',[target.toString(),'-X','-v','ON_ERROR_STOP=1','-q','-f',kit+'/snapshot.sql'],{stdio:'pipe'});
  await assertDisposableDatabase(db);
  assert.equal((await db.query('SELECT current_database() name')).rows[0].name,name);
  // Match the canonical bootstrap application owner, never widen API roles.
  await db.query(`ALTER SCHEMA public OWNER TO postgres; ALTER SCHEMA eshop OWNER TO postgres; ALTER SCHEMA analytics OWNER TO postgres;
   DO $owner$ DECLARE r record; BEGIN
    FOR r IN SELECT c.oid::regclass object,c.relkind FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','eshop','analytics') AND c.relkind IN ('r','p','S') ORDER BY c.relkind='S' LOOP
     EXECUTE format('ALTER %s %s OWNER TO postgres',CASE WHEN r.relkind='S' THEN 'SEQUENCE' ELSE 'TABLE' END,r.object);
    END LOOP;
    FOR r IN SELECT p.oid::regprocedure object FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
     WHERE n.nspname='public' AND p.prokind IN ('f','w') AND NOT EXISTS(SELECT 1 FROM pg_depend d WHERE d.classid='pg_proc'::regclass AND d.objid=p.oid AND d.deptype='e') LOOP
     EXECUTE format('ALTER FUNCTION %s OWNER TO postgres',r.object);
    END LOOP;
   END $owner$;`);
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
from pathlib import Path
sys.path.insert(0,'automation')
from generate_canonical_source_contract import definitions,statements
frozen=Path('supabase/migrations/20261106120000_payment_provider_connectors.sql').read_text()
hardening=Path('supabase/migrations/20261106160000_payment_provider_hardening.sql').read_text()
previous={}
for statement in statements(frozen):
 for signature,body in definitions(statement):
  if body is not None:previous[signature]=statement
changed={signature for signature,body in definitions(hardening) if body is not None}
for signature in sorted(changed-previous.keys()):print('DROP FUNCTION IF EXISTS '+signature+' CASCADE;')
for signature,statement in previous.items():
 if signature in changed:print(statement)
`],{cwd:root,encoding:'utf8',maxBuffer:8*1024*1024});
   await db.query('ALTER TABLE eshop.payment_info DROP CONSTRAINT payment_info_registered_method, DROP CONSTRAINT payment_info_stripe_connection_identity');
   await db.query(sql);
   assert.equal((await db.query("SELECT to_regprocedure('public.payment_sale_policy_internal()') IS NULL ready")).rows[0].ready,true,'frozen connector predecessor reconstructed');
  }
  await run(db);
 }finally{
  if(db){await db.query('ROLLBACK').catch(()=>{});await db.end();}
  if(created)await admin.query(`DROP DATABASE ${name} WITH (FORCE)`);
  await admin.end();await rm(kit,{recursive:true,force:true});
 }
}
