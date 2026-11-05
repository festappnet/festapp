import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const url=process.env.DATABASE_URL;assertLocalDatabaseUrl(url);
async function connection(){const c=new Client({connectionString:url});await c.connect();await c.query("SET request.jwt.claim.role='service_role'; SET statement_timeout='10s'");return c;}
const value=async(c,sql,args=[])=>(await c.query(sql,args)).rows[0].result;
async function waiting(c,pid){for(let n=0;n<100;n++){const r=await c.query('SELECT wait_event_type FROM pg_stat_activity WHERE pid=$1',[pid]);if(r.rows[0]?.wait_event_type==='Lock')return;await new Promise(r=>setTimeout(r,10));}throw Error('Expected actual concurrent form lock');}

test('actual save, subscription, maintenance and unsubscribe transactions serialize without duplicate launch',{timeout:45000},async()=>{
 const [db,left,right]=await Promise.all([connection(),connection(),connection()]);await assertDisposableDatabase(db);
 let org,unit,occasion,form;
 try{
  org=await value(db,"INSERT INTO public.organizations(title) VALUES('Sale opening concurrency') RETURNING id result");
  unit=await value(db,"INSERT INTO public.units(title,organization) VALUES('Synthetic organizer',$1) RETURNING id result",[org]);
  occasion=await value(db,"INSERT INTO public.occasions(title,link,organization,unit,start_time,end_time) VALUES('Synthetic ball',$1,$2,$3,now(),now()+interval '2 days') RETURNING id result",[randomUUID(),org,unit]);
  form=await value(db,"INSERT INTO public.forms(occasion,is_open,data) VALUES($1,true,jsonb_build_object('schedule',jsonb_build_object('start_time',now()+interval '1 day'),'sale_opening_notifications','{\"enabled\":true}'::jsonb)) RETURNING id result",[occasion]);
  const link=await value(db,"SELECT public.reserve_public_link_internal('form',$1,NULL,true) result",[form]);
  await db.query('UPDATE public.forms SET link=$2 WHERE id=$1',[form,link]);
  await db.query('SELECT public.sync_sale_opening_settings_internal($1,NULL)',[form]);
  const unsubscribe='f'.repeat(64);
  const payload={formLink:link,email:`race-${randomUUID()}@example.invalid`,lang:'cs',unsubscribe:{hash:unsubscribe,envelope:{v:'1',ciphertext:'y'.repeat(48)}}};
  await db.query("SELECT public.sale_opening_notification_command('subscribe',$1)",[payload]);
  await left.query('BEGIN');
  await left.query("SELECT public.sale_opening_notification_command('subscribe',$1)",[payload]);
  const pid=await value(right,'SELECT pg_backend_pid() result');
  const repeated=right.query("SELECT public.sale_opening_notification_command('subscribe',$1)",[payload]);
  await waiting(db,pid);await left.query('COMMIT');await repeated;
  assert.equal(await value(db,"SELECT count(*)::int result FROM public.sale_opening_subscriptions s JOIN public.sale_opening_campaigns c ON c.id=s.campaign_id WHERE c.form_id=$1 AND s.state='active'",[form]),1);
  // Save uses the actual aggregate mutation and contends with subscription.
  await left.query('BEGIN');
  const saved=await value(left,"SELECT public.update_form_internal_v1($1) result",[{id:form,occasion,settings:{schedule:{start_time:new Date(Date.now()+60000).toISOString()}}}]);
  assert.equal(saved.code,200,JSON.stringify(saved));
  const verifyDuringSave=right.query("SELECT public.sale_opening_notification_command('subscribe',$1)",[payload]);
  await waiting(db,pid);await left.query('COMMIT');await verifyDuringSave;
  await db.query("UPDATE public.forms SET data=jsonb_set(data,'{schedule,start_time}',to_jsonb(now()-interval '1 minute')) WHERE id=$1",[form]);
  await Promise.all([left.query('SELECT public.maintain_sale_opening_notifications(100)'),right.query('SELECT public.maintain_sale_opening_notifications(100)')]);
  const message=await value(db,"SELECT to_jsonb(m) result FROM public.email_messages m WHERE m.occasion=$1 AND m.message_kind='sale_opening_opened'",[occasion]);
  assert.ok(message);
  assert.equal(await value(db,"SELECT count(*)::int result FROM public.email_messages WHERE occasion=$1 AND message_kind='sale_opening_opened'",[occasion]),1);
  // The send fence and unsubscribe serialize on the exact same form lock.
  await left.query('BEGIN');
  const lease=randomUUID();
  await left.query("UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=10,daily_quota=1000,provider_sent_24h=0,worker_url=NULL,next_send_at=now(),circuit_until=NULL,provider_outage_streak=0,probe_until=NULL");
  await left.query("UPDATE public.email_messages SET workflow_state='preparing',lease_token=$2,lease_until=now()+interval '90 seconds' WHERE message_id=$1",[message.message_id,lease]);
  const attempt=await value(left,"INSERT INTO public.email_attempts(message_id,lease_token,state) VALUES($1,$2,'preparing') RETURNING attempt_id result",[message.message_id,lease]);
  await left.query('SELECT public.prepare_email($1,$2,$3)',[message.message_id,lease,{sealed:'test snapshot'}]);
  const permit=await value(left,'SELECT public.begin_email_send($1,$2) result',[attempt,lease]);
  assert.equal(permit.disposition,'send');
  const leave=right.query("SELECT public.sale_opening_notification_command('unsubscribe',$1)",[{tokenHash:unsubscribe}]);
  await waiting(db,pid);await left.query('ROLLBACK');await leave;
  assert.equal(await value(db,'SELECT public.email_intent_valid(m) result FROM public.email_messages m WHERE message_id=$1',[message.message_id]),false);
  await Promise.all([left.query('SELECT public.maintain_sale_opening_notifications(100)'),right.query('SELECT public.maintain_sale_opening_notifications(100)')]);
  assert.equal(await value(db,"SELECT count(*)::int result FROM public.email_messages WHERE occasion=$1 AND message_kind='sale_opening_opened'",[occasion]),1);
 }finally{
  await Promise.allSettled([left.query('ROLLBACK'),right.query('ROLLBACK')]);
  if(org){
   await db.query('BEGIN');
   await db.query('DELETE FROM public.email_attempts WHERE message_id IN (SELECT message_id FROM public.email_messages WHERE organization=$1)',[org]);
   await db.query('DELETE FROM public.email_messages WHERE organization=$1',[org]);
   if(form)await db.query('DELETE FROM public.forms WHERE id=$1',[form]);
   if(occasion)await db.query('DELETE FROM public.occasions WHERE id=$1',[occasion]);
   if(unit)await db.query('DELETE FROM public.units WHERE id=$1',[unit]);
   // Scope IDs may have audit/tombstone references. Their synthetic tenant is
   // retained rather than deleting shared registries or changing cleanup guards.
   await db.query('COMMIT');
  }
  await Promise.all([db.end(),left.end(),right.end()]);
 }
});
