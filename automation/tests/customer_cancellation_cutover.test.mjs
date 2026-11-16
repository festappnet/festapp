import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {createTestWorkspace} from '../../web_client/tests/database/runtime_workspace.js';
import {assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const {Client}=createRequire(new URL('../../web_client/package.json',import.meta.url))('pg');
const read=p=>readFileSync(new URL('../../'+p,import.meta.url),'utf8');
const migration=read('supabase/migrations/20261116010000_customer_cancellation_cutover.sql');

test('actual forward refuses term or enabled-move state and rolls back without discarding data',async()=>{
 const lease=await createTestWorkspace();const db=new Client({connectionString:lease.databaseUrl});
 try{
  await db.connect();await assertDisposableDatabase(db);
  await db.query('BEGIN; SET LOCAL statement_timeout=\'30s\'; SET LOCAL lock_timeout=\'5s\'');
  await db.query(read('database/tests/helpers/assertions.sql')+'\n'+read('database/tests/helpers/payment_lifecycle_fixture.sql'));
  const x=(await db.query('SELECT pg_temp.payment_fixture() x')).rows[0].x;
  // Reconstitute the precise removed fields to exercise pre-cutover state.
  await db.query('ALTER TABLE public.forms ADD COLUMN term_start_at timestamptz, ADD COLUMN term_end_at timestamptz; ALTER TABLE eshop.customer_order_change_requests ADD COLUMN target_form_id bigint');
  const before=(await db.query("SELECT md5(prosrc) hash FROM pg_proc WHERE oid='public.normalize_customer_order_policy_internal(jsonb)'::regprocedure")).rows[0].hash;
  for(const state of ['date','policy']){
   if(state==='date')await db.query("UPDATE public.forms SET term_start_at='2027-01-01T12:00:00Z' WHERE id=$1",[x.form]);
   else {
    await db.query('UPDATE public.forms SET term_start_at=NULL WHERE id=$1',[x.form]);
    await db.query("INSERT INTO eshop.customer_order_change_policies(form_id,revision,policy) VALUES($1,1,'{\"move\":{\"enabled\":true,\"targets\":[]}}')",[x.form]);
   }
   const snapshot=(await db.query('SELECT to_jsonb(f) value FROM public.forms f WHERE id=$1',[x.form])).rows[0].value;
   await db.query('SAVEPOINT before_cutover');
   await assert.rejects(()=>db.query(migration),e=>e.message==='Term-moving state requires explicit preservation before cutover');
   await db.query('ROLLBACK TO SAVEPOINT before_cutover');
   assert.deepEqual((await db.query('SELECT to_jsonb(f) value FROM public.forms f WHERE id=$1',[x.form])).rows[0].value,snapshot);
   assert.equal((await db.query("SELECT md5(prosrc) hash FROM pg_proc WHERE oid='public.normalize_customer_order_policy_internal(jsonb)'::regprocedure")).rows[0].hash,before);
  }
 }finally{await db.query('ROLLBACK').catch(()=>{});await db.end();await lease.release();}
});


test('preflight fences a concurrent term write and then preserves its committed state',async()=>{
 const lease=await createTestWorkspace();const writer=new Client({connectionString:lease.databaseUrl});const cutover=new Client({connectionString:lease.databaseUrl});
 let pending;
 try{
  await writer.connect();await cutover.connect();await assertDisposableDatabase(writer);
  await writer.query(read('database/tests/helpers/assertions.sql')+'\n'+read('database/tests/helpers/payment_lifecycle_fixture.sql'));
  const x=(await writer.query('SELECT pg_temp.payment_fixture() x')).rows[0].x;
  await writer.query('ALTER TABLE public.forms ADD COLUMN term_start_at timestamptz, ADD COLUMN term_end_at timestamptz; ALTER TABLE eshop.customer_order_change_requests ADD COLUMN target_form_id bigint');
  await writer.query('BEGIN');await writer.query("UPDATE public.forms SET term_start_at='2027-01-01T12:00:00Z' WHERE id=$1",[x.form]);
  await cutover.query("BEGIN; SET LOCAL lock_timeout='10s'");
  let completed=false;
  pending=cutover.query(read('database/functions/customer_order_changes/retire_move_preflight.sql')).then(()=>({ok:true}),error=>({error})).finally(()=>completed=true);
  let blocked=false;const deadline=Date.now()+5000;
  while(!completed && Date.now()<deadline){
   blocked=(await writer.query('SELECT $1::int=ANY(pg_blocking_pids($2)) blocked',[writer.processID,cutover.processID])).rows[0].blocked;
   if(blocked)break;
   await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert.equal(blocked,true,'cutover waits for the old writer before inspecting state');
  await writer.query('COMMIT');
  const result=await pending;assert.equal(result.error?.message,'Term-moving state requires explicit preservation before cutover');
  await cutover.query('ROLLBACK');
  assert.equal((await writer.query('SELECT term_start_at IS NOT NULL saved FROM public.forms WHERE id=$1',[x.form])).rows[0].saved,true);
 }finally{
  await writer.query('ROLLBACK').catch(()=>{});await cutover.query('ROLLBACK').catch(()=>{});await pending?.catch(()=>{});
  await writer.end();await cutover.end();await lease.release();
 }
});
