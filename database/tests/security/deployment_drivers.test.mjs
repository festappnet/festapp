import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync} from 'node:fs';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const configured=new URL(process.env.DATABASE_URL);
assert.equal(configured.hostname,'127.0.0.1');assert.equal(configured.port,'55562');
configured.username='supabase_admin';
test('phase drivers fail on wrong target and atomically record exact migrations on guarded local substitute',async()=>{
 const db=new Client({connectionString:configured.href});await db.connect();
 try{
  await db.query('BEGIN');
  const {rows:[marker]}=await db.query('SELECT project FROM festapp_test_support.disposable_environment');
  assert.equal(marker.project,'festapp-security-remediation-20261016');
  const manifest=JSON.parse(readFileSync(new URL('../../../automation/hetzner-supabase/runtime/server-security-release.json',import.meta.url)));
  for(const phase of manifest.phases){
   const driver=readFileSync(new URL('../../../'+phase.driver,import.meta.url),'utf8').replace(/^\\set.*$/mg,'').replace(/^BEGIN;|^COMMIT;/mg,'');
   await db.query('SAVEPOINT target');
   await assert.rejects(db.query(driver),/Canonical target mismatch/);
   await db.query('ROLLBACK TO SAVEPOINT target');
   await db.query('DELETE FROM supabase_migrations.schema_migrations WHERE version=$1',[phase.version]);
   // Target substitution is possible only in this local test, after identity assertion.
   await db.query(driver.replace("current_database()<>'festapp_rehearsal_20260909220601'","current_database()<>'postgres'"));
   const {rows:[row]}=await db.query('SELECT statements FROM supabase_migrations.schema_migrations WHERE version=$1',[phase.version]);
   assert.deepEqual(row.statements,['-- sha256:'+phase.sha256]);
  }
 }finally{await db.query('ROLLBACK');await db.end();}
});
