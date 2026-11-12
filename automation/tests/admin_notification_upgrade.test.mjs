import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
test('legacy drain gate rolls back pending cancellation while unknown exists, then retains accepted audit', {skip:!process.env.DATABASE_URL}, async()=>{
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try{
  await assertDisposableDatabase(db);await db.query('BEGIN');
  await db.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
  const {rows:[org]}=await db.query("INSERT INTO public.organizations(title) VALUES('Legacy bank upgrade') RETURNING id");
  await db.query('SAVEPOINT retired_producer');
  await assert.rejects(db.query("SELECT public.enqueue_email('custom',jsonb_build_object('organization',$1::bigint),'fixture@example.test','{}','retired-producer','BANK_SYNC_WARNING')",[org.id]),/bank_warning_producer_retired/);
  await db.query('ROLLBACK TO SAVEPOINT retired_producer');
  const {rows:[identity]}=await db.query('SELECT gen_random_uuid() id,gen_random_uuid() incident');
  await db.query('INSERT INTO auth.users(id) VALUES($1)',[identity.id]);
  await db.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[identity.id,org.id]);
  const ids={};
  for(const state of ['pending','unknown','accepted']){
   const {rows:[row]}=await db.query("INSERT INTO public.email_messages(organization,target_time,code,data,message_kind,dedupe_key,input_hash,workflow_state,prepared) VALUES($1,now(),'BANK_SYNC_WARNING','{}','custom',$2,$2,$2,'{\"historical\":true}') RETURNING message_id",[org.id,state]);ids[state]=row.message_id;
  }
  await db.query("UPDATE public.email_messages SET recipient_user=$1,data=jsonb_build_object('connection_id',91,'incident_id',$2::text) WHERE message_id=$3",[identity.id,identity.incident,ids.accepted]);
  const cutover=readFileSync('database/functions/notification_center/email_bank_cutover.sql','utf8');
  await db.query('SAVEPOINT blocked_upgrade');
  await assert.rejects(db.query(cutover),/legacy_bank_notification_drain_required/);
  await db.query('ROLLBACK TO SAVEPOINT blocked_upgrade');
  assert.equal((await db.query('SELECT workflow_state FROM public.email_messages WHERE message_id=$1',[ids.pending])).rows[0].workflow_state,'pending');
  await db.query("SELECT public.reconcile_unknown_email($1,'accepted','synthetic provider receipt for upgrade gate','upgrade-fake-provider')",[ids.unknown]);
  await db.query(cutover);
  assert.equal((await db.query('SELECT workflow_state FROM public.email_messages WHERE message_id=$1',[ids.pending])).rows[0].workflow_state,'cancelled');
  assert.equal((await db.query('SELECT stopped FROM public.notification_center_email_profiles WHERE recipient=$1',[identity.id])).rows[0].stopped,true);
  assert.equal((await db.query('SELECT count(*)::int n FROM public.notification_center_email_subscriptions WHERE recipient=$1',[identity.id])).rows[0].n,0);
  assert.equal((await db.query('SELECT delivery_key,disposition FROM public.notification_center_email_items WHERE recipient=$1',[identity.id])).rows[0].delivery_key,'bank:91:incident:'+identity.incident);
  for(const id of [ids.accepted,ids.unknown]){
   const {rows:[row]}=await db.query('SELECT workflow_state,prepared FROM public.email_messages WHERE message_id=$1',[id]);
   assert.equal(row.workflow_state,'accepted');assert.deepEqual(row.prepared,{historical:true});
  }
 }finally{await db.query('ROLLBACK');await db.end();}
});
