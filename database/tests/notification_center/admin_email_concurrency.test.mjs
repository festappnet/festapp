import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
async function connect(){const c=new Client({connectionString,statement_timeout:10000});await c.connect();await assertDisposableDatabase(c);return c;}
async function fixture(c){
 const user=randomUUID();
 await c.query('INSERT INTO auth.users(id) VALUES($1)',[user]);
 const {rows:[org]}=await c.query("INSERT INTO public.organizations(title) VALUES('Souběžné souhrny') RETURNING id");
 await c.query("INSERT INTO public.user_info(id,organization,email_delivery) VALUES($1,$2,'concurrency@example.test')",[user,org.id]);
 const {rows:[oc]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Ples',$2,now(),now()+interval '1 day') RETURNING id",[org.id,randomUUID()]);
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES($1,$2,true)',[oc.id,user]);
 await c.query("INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES($1,now()-interval '1 day')",[org.id]);
 await c.query('UPDATE public.email_capacity SET quota_at=now(),daily_quota=100000,allocated_daily=100000');
 await c.query('SELECT public.activate_notification_center_emails($1)',[org.id]);
 await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);
 await c.query("SELECT public.save_notification_center_email_settings($1,NULL,0,false,'cs','{\"order_created\":true}')",[org.id]);
 await publish(c,{org:org.id,oc:oc.id});
 return {org:org.id,oc:oc.id,user};
}
async function publish(c,f){await c.query("SELECT public.notification_center_publish_internal($1,$2,'order_created',$3,'{\"count\":2,\"formContext\":{\"allowsMultiple\":true}}')",[f.org,f.oc,randomUUID()]);await c.query('SELECT public.project_notification_center(500)');}
async function due(c,f){await c.query("UPDATE public.notification_center_email_dispatches SET opened_at=opened_at-interval '301 seconds',due_at=due_at-interval '301 seconds' WHERE recipient=$1 AND state='collecting'",[f.user]);}
async function state(c,f){return (await c.query(`SELECT (SELECT count(*)::int FROM public.notification_center_email_items WHERE recipient=$1) items,
 (SELECT count(*)::int FROM public.notification_center_email_dispatches WHERE recipient=$1 AND state='collecting') collecting,
 (SELECT count(*)::int FROM public.email_messages WHERE recipient_user=$1) messages`,[f.user])).rows[0];}
test('recipient profile serializes two collectors, cursor commit and lost enqueue response',async()=>{
 const setup=await connect(),one=await connect(),two=await connect();
 try{
  const f=await fixture(setup);
  await one.query('BEGIN');
  await one.query('SELECT public.collect_notification_center_emails(100)');
  // A second real worker skips the uncommitted profile; it cannot steal its cursor.
  assert.equal((await two.query('SELECT public.collect_notification_center_emails(100) n')).rows[0].n,0);
  await one.query('ROLLBACK');
  assert.deepEqual(await state(setup,f),{items:0,collecting:0,messages:0});
  await Promise.all([one.query('SELECT public.collect_notification_center_emails(100)'),two.query('SELECT public.collect_notification_center_emails(100)')]);
  assert.deepEqual(await state(setup,f),{items:1,collecting:1,messages:0});
  await due(setup,f);
  // The committed result is deliberately discarded, as with HTTP loss after commit.
  await one.query('SELECT public.enqueue_notification_center_emails(100)');
  await Promise.all([one.query('SELECT public.enqueue_notification_center_emails(100)'),two.query('SELECT public.enqueue_notification_center_emails(100)')]);
  assert.deepEqual(await state(setup,f),{items:1,collecting:0,messages:1});
  await publish(setup,f);
  await Promise.all([one.query('SELECT public.collect_notification_center_emails(100)'),two.query('SELECT public.collect_notification_center_emails(100)')]);
  await due(setup,f);
  await setup.query("UPDATE public.email_messages SET workflow_state='unknown' WHERE recipient_user=$1",[f.user]);
  await one.query('SELECT public.enqueue_notification_center_emails(100)');
  assert.deepEqual(await state(setup,f),{items:2,collecting:1,messages:1});
  await setup.query("UPDATE public.email_messages SET workflow_state='accepted' WHERE recipient_user=$1",[f.user]);
  await two.query('SELECT public.enqueue_notification_center_emails(100)');
  assert.deepEqual(await state(setup,f),{items:2,collecting:0,messages:2});
 }finally{for(const c of [setup,one,two]){await c.query('ROLLBACK');await c.end();}}
});
test('collect commit survives an enqueue failure; concurrent close and new delivery lose no membership',async()=>{
 const setup=await connect(),one=await connect(),two=await connect();
 try{
  const f=await fixture(setup);
  await one.query('SELECT public.collect_notification_center_emails(100)');
  await due(setup,f);
  await one.query('BEGIN');
  await one.query("UPDATE public.abuse_policy_rules SET base_limit=1 WHERE rule_key='email.payload.bytes'");
  assert.equal((await one.query('SELECT public.enqueue_notification_center_emails(100) n')).rows[0].n,0);
  assert.equal((await one.query("SELECT next_attempt_at>now() deferred FROM public.notification_center_email_dispatches WHERE recipient=$1 AND state='collecting'",[f.user])).rows[0].deferred,true);
  await one.query('ROLLBACK');
  assert.deepEqual(await state(setup,f),{items:1,collecting:1,messages:0});
  await Promise.all([publish(two,f),one.query('SELECT public.enqueue_notification_center_emails(100)')]);
  await two.query('SELECT public.collect_notification_center_emails(100)');
  assert.equal((await state(setup,f)).items,2);
  assert.equal((await setup.query('SELECT count(DISTINCT event_id)::int n FROM public.notification_center_email_item_sources WHERE recipient=$1',[f.user])).rows[0].n,2);
 }finally{for(const c of [setup,one,two]){await c.query('ROLLBACK');await c.end();}}
});
test('two send workers obtain one permit; replay cannot cross the same attempt twice',async()=>{
 const setup=await connect(),one=await connect(),two=await connect();
 try{
  const f=await fixture(setup);await setup.query('SELECT public.collect_notification_center_emails(100)');await due(setup,f);await setup.query('SELECT public.enqueue_notification_center_emails(100)');
  await setup.query("UPDATE public.email_messages SET target_time='infinity' WHERE recipient_user IS DISTINCT FROM $1",[f.user]);
  await setup.query("UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=100,daily_quota=100000,provider_sent_24h=0,next_send_at='-infinity',circuit_until=NULL,probe_until=NULL");
  for(const c of [setup,one,two])await c.query("SELECT set_config('request.jwt.claim.role','service_role',false)");
  const {rows:[{claim}]}=await setup.query('SELECT public.claim_email() claim');
  const {rows:[{context}]}=await setup.query('SELECT public.notification_center_email_context_internal($1,$2) context',[claim.data.dispatchId,f.user]);
  await setup.query('SELECT public.prepare_email($1,$2,$3,$4)',[claim.message_id,claim.lease_token,{sealed:'fake-provider-boundary'},{notification_fingerprint:context.fingerprint}]);
  const results=await Promise.all([one.query('SELECT public.begin_email_send($1,$2) result',[claim.attempt_id,claim.lease_token]),two.query('SELECT public.begin_email_send($1,$2) result',[claim.attempt_id,claim.lease_token])]);
  assert.deepEqual(results.map(r=>r.rows[0].result.disposition).sort(),['replay','send']);
  assert.equal((await setup.query('SELECT attempt_count FROM public.email_messages WHERE message_id=$1',[claim.message_id])).rows[0].attempt_count,1);
  await setup.query("SELECT public.finish_email_attempt($1,$2,'accepted',$3)",[claim.attempt_id,claim.lease_token,'concurrency-fake-'+randomUUID()]);
 }finally{for(const c of [setup,one,two]){await c.query('ROLLBACK');await c.end();}}
});

test('first required profile enrollment skips an uncommitted creator and survives rollback',async()=>{
 const setup=await connect(),one=await connect(),two=await connect();
 const user=randomUUID();
 try{
  await setup.query('INSERT INTO auth.users(id) VALUES($1)',[user]);
  await setup.query('INSERT INTO public.user_info(id) VALUES($1)',[user]);
  await one.query('BEGIN');
  assert.equal((await one.query('SELECT public.notification_center_email_ensure_profile_internal($1,true) ok',[user])).rows[0].ok,true);
  await two.query("SET statement_timeout='1s'");
  assert.equal((await two.query('SELECT public.notification_center_email_ensure_profile_internal($1,true) ok',[user])).rows[0].ok,false);
  await one.query('ROLLBACK');
  assert.equal((await two.query('SELECT public.notification_center_email_ensure_profile_internal($1,true) ok',[user])).rows[0].ok,true);
  assert.equal((await setup.query('SELECT stopped FROM public.notification_center_email_profiles WHERE recipient=$1',[user])).rows[0].stopped,true);
 }finally{
  await one.query('ROLLBACK');
  await setup.query('DELETE FROM public.notification_center_email_profiles WHERE recipient=$1',[user]);
  await setup.query('DELETE FROM public.user_info WHERE id=$1',[user]);
  await setup.query('DELETE FROM auth.users WHERE id=$1',[user]);
  await Promise.all([setup.end(),one.end(),two.end()]);
 }
});

test('connector episode creation serializes across workers and rollback cannot duplicate an alert',async()=>{
 const setup=await connect(),one=await connect(),two=await connect();
 try{
  const f=await fixture(setup);
  const {rows:[unit]}=await setup.query("INSERT INTO public.units(organization,title) VALUES($1,'Správa brány') RETURNING id",[f.org]);
  await setup.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[unit.id,f.user]);
  const {rows:[conn]}=await setup.query("INSERT INTO eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state) VALUES($1,$2,$3,false,'restricted') RETURNING id",[f.org,unit.id,'acct_notify'+randomUUID().replaceAll('-','')]);
  const project=(db)=>db.query("SELECT public.notification_center_provider_connection_internal('stripe',$1)",[conn.id]);
  await one.query('BEGIN');await project(one);
  await two.query('BEGIN');
  const pid=(await two.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const waiting=project(two);
  let overlapping=false;
  for(let i=0;i<100;i++){
   overlapping=(await setup.query('SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=$1 AND NOT granted) waiting',[pid])).rows[0].waiting;
   if(overlapping)break;
   await new Promise(resolve=>setTimeout(resolve,10));
  }
  assert(overlapping,'workers really overlap on the shared connection episode');
  await one.query('ROLLBACK');await waiting;await two.query('COMMIT');
  await Promise.all([project(one),project(two)]);
  assert.equal((await setup.query('SELECT count(*)::int n FROM eshop.provider_connection_notification_incidents WHERE connection_id=$1',[conn.id])).rows[0].n,1);
  assert.equal((await setup.query("SELECT count(*)::int n FROM public.notification_center_events WHERE data->>'connectionId'=$1 AND kind='provider_problem'",[conn.id])).rows[0].n,1);
  await setup.query('SELECT public.project_notification_center(500)');
  await Promise.all([one.query('SELECT public.collect_notification_center_emails(100)'),two.query('SELECT public.collect_notification_center_emails(100)')]);
  assert.equal((await state(setup,f)).items,2,'one optional event plus one required connection episode');
 }finally{
  await one.query('ROLLBACK');await two.query('ROLLBACK');
  await Promise.all([setup.end(),one.end(),two.end()]);
 }
});
