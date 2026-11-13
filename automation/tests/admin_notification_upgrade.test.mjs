import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
test('payment channel migration retracts retained app views and badges while preserving history', {skip:!process.env.DATABASE_URL}, async()=>{
 assertLocalDatabaseUrl(process.env.DATABASE_URL);
 const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();
 try {
  await assertDisposableDatabase(db);await db.query('BEGIN');
  await db.query('SELECT pg_advisory_xact_lock(5831290471284)');
  await db.query(readFileSync('database/tests/helpers/prepared_notification_view.sql','utf8'));
  const legacy=readFileSync('supabase/migrations/20261112234500_admin_notification_delivery.sql','utf8')
   .match(/CREATE OR REPLACE FUNCTION public\.notification_center_prepared_policy\([\s\S]*?\$\$;/)?.[0];
  assert.ok(legacy,'published policy supplies the actual previous app behavior');
  await db.query(legacy);
  const {rows:[org]}=await db.query("INSERT INTO public.organizations(title) VALUES('Přehled pořadatele') RETURNING id");
  const {rows:[user]}=await db.query('INSERT INTO auth.users(id) VALUES(gen_random_uuid()) RETURNING id');
  await db.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[user.id,org.id]);
  const {rows:[occasion]}=await db.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Společenský ples',gen_random_uuid()::text,now(),now()+interval '1 day') RETURNING id",[org.id]);
  await db.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES($1,$2,true)',[occasion.id,user.id]);
  await db.query("INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES($1,now()-interval '1 day')",[org.id]);
  await db.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[user.id]);
  await db.query("SELECT public.notification_center_publish_internal($1,$2,'order_payment_received','payment:upgrade','{}'),public.notification_center_publish_internal($1,$2,'order_created','order:upgrade','{\"count\":1,\"formContext\":{\"allowsMultiple\":false}}')",[org.id,occasion.id]);
  await db.query('SELECT public.project_notification_center(500)');
  const {rows:[before]}=await db.query('SELECT pg_temp.prepared_notification_view($1,$2,p_keep_view=>true) value',[org.id,occasion.id]);
  assert.equal(before.value.items.length,2,'legacy snapshot includes the payment notice');
  const order=before.value.items.find(item=>item.kind==='order_created');
  await db.query('SELECT public.mark_notification_center_view_item_read($1,$2)',[org.id,{viewToken:before.value.viewToken,id:order.id}]);
  const {rows:[receipt]}=await db.query('SELECT count(*)::int count FROM public.notification_center_read_batches WHERE organization=$1 AND recipient=$2',[org.id,user.id]);
  assert.ok(receipt.count>0);
  await db.query(readFileSync('supabase/migrations/20261113123000_notification_payment_channels.sql','utf8'));
  const {rows:[pending]}=await db.query('SELECT public.get_notification_center_prepared_badge($1) value',[org.id]);
  assert.equal(pending.value.state,'preparing','upgrade makes stale cached badges wait for normal repair');
  const {rows:[after]}=await db.query("SELECT pg_temp.prepared_notification_view($1,$2,p_mode=>'refresh',p_view=>$3,p_keep_view=>true) value",[org.id,occasion.id,before.value.viewToken]);
  assert.equal(after.value.state,'ready');
  assert.ok(!after.value.items.some(item=>item.state==='ready'&&item.kind==='order_payment_received'),'an already open snapshot retracts payment notices');
  const {rows:[badge]}=await db.query('SELECT public.get_notification_center_prepared_badge($1) value',[org.id]);
  assert.equal(badge.value.unread,false,'removed payment cannot keep the bell unread');
  const {rows:[history]}=await db.query('SELECT (SELECT count(*)::int FROM public.notification_center_events WHERE organization=$1) events,(SELECT count(*)::int FROM public.notification_center_deliveries WHERE organization=$1) deliveries,(SELECT count(*)::int FROM public.notification_center_read_batches WHERE organization=$1 AND recipient=$2) receipts',[org.id,user.id]);
  assert.deepEqual(history,{events:2,deliveries:2,receipts:receipt.count});
 } finally {await db.query('ROLLBACK');await db.end();}
});
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
