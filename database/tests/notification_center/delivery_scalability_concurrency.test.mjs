import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
import {drain} from '../../../automation/notification-center/drain.mjs';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
async function connect(){const c=new Client({connectionString});await c.connect();await assertDisposableDatabase(c);await c.query("SET statement_timeout='5s'");return c;}
async function fixture(c,n=1){
 const user=randomUUID();
 const {rows:[{id:org}]}=await c.query("INSERT INTO public.organizations(title) VALUES('Delivery scalability') RETURNING id");
 await c.query('INSERT INTO auth.users(id) VALUES($1)',[user]);
 await c.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[user,org]);
 const {rows:[{id:oc}]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Delivery',$2,now(),now()+interval '1 day') RETURNING id",[org,randomUUID()]);
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES($1,$2,true)',[oc,user]);
 await c.query('INSERT INTO public.notification_center_organizations(organization) VALUES($1)',[org]);
 await c.query('INSERT INTO public.notification_center_user_state(organization,recipient) VALUES($1,$2)',[org,user]);
 await c.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','work:'||i) FROM generate_series(1,$3::int) i",[org,oc,n]);
 return {org,oc,user};
}
async function state(c,f){return (await c.query('SELECT last_delivery_sequence::int last FROM public.notification_center_user_state WHERE organization=$1 AND recipient=$2',[f.org,f.user])).rows[0].last;}
async function cleanup(c,fixtures){for(const f of fixtures){await c.query('DELETE FROM public.occasion_users WHERE occasion=$1',[f.oc]);await c.query('DELETE FROM public.occasions WHERE id=$1',[f.oc]);await c.query('DELETE FROM public.user_info WHERE id=$1',[f.user]);await c.query('DELETE FROM public.organizations WHERE id=$1',[f.org]);await c.query('DELETE FROM auth.users WHERE id=$1',[f.user]);}}
test('locked personal state defers progress while another tenant commits; rollback and retry preserve sequences',async()=>{
 const c=await connect(),hot=await connect(),worker=await connect();const fs=[];
 try{
  const a=await fixture(c,20),b=await fixture(c,3);fs.push(a,b);
  await hot.query('BEGIN');await hot.query('SELECT 1 FROM public.notification_center_user_state WHERE organization=$1 AND recipient=$2 FOR UPDATE',[a.org,a.user]);
  const start=performance.now();await worker.query('SELECT public.project_notification_center(100)');
  assert.ok(performance.now()-start<1000,'worker is not waiting on hot user');
  assert.equal(await state(c,a),0);assert.equal(await state(c,b),3);
  assert.equal((await c.query('SELECT count(*)::int n FROM public.notification_center_recipients r JOIN public.notification_center_events e ON e.id=r.event_id WHERE e.organization=$1 AND r.processed_revision>0',[a.org])).rows[0].n,0);
  await hot.query('ROLLBACK');
  await worker.query('BEGIN');await worker.query('SELECT public.project_notification_center(100)');await worker.query('ROLLBACK');
  assert.equal(await state(c,a),0,'crash before commit rolls back sequence and progress');
  for(let i=0;i<30;i++){
   await drain(worker);if(await state(c,a)===20)break;
   await new Promise(resolve=>setTimeout(resolve,50));
  }
  assert.equal(await state(c,a),20);
  await drain(worker);assert.equal(await state(c,a),20,'repeat drain does not redeliver');
 }finally{await hot.query('ROLLBACK');try{await cleanup(c,fs);}finally{await Promise.all([c.end(),hot.end(),worker.end()]);}}
});
test('bad recipient revision backs off, quarantines without false progress, and supports explicit repair',async()=>{
 const c=await connect();const fs=[];
 try{
  const bad=await fixture(c),good=await fixture(c,2);fs.push(bad,good);
  // A corrupt server timezone fails inside the real delivery INSERT, after sequence allocation.
  const {rows:[{id}]}=await c.query('SELECT id FROM public.notification_center_events WHERE organization=$1',[bad.org]);
  await c.query("UPDATE public.notification_center_organizations SET timezone='invalid-zone' WHERE organization=$1",[bad.org]);
  for(let i=0;i<5;i++){
   await c.query('UPDATE public.notification_center_recipients SET next_attempt_at=clock_timestamp() WHERE event_id=$1',[id]);
   await c.query('SELECT public.project_notification_center(100)');
  }
  const {rows:[r]}=await c.query('SELECT retry_count,quarantined,last_error_code,processed_revision::int FROM public.notification_center_recipients WHERE event_id=$1',[id]);
  assert.deepEqual(r,{retry_count:5,quarantined:true,last_error_code:'22023',processed_revision:0});
  assert.equal(await state(c,bad),0);assert.equal(await state(c,good),2);
  await c.query('SELECT public.project_notification_center(100)');
  assert.equal((await c.query('SELECT retry_count FROM public.notification_center_recipients WHERE event_id=$1',[id])).rows[0].retry_count,5,'quarantine stops retry storm');
  const health=(await c.query('SELECT public.get_notification_center_delivery_health() h')).rows[0].h;
  assert.ok(health.organizations.some(x=>x.organization===Number(bad.org)&&x.quarantined===1));
  assert.equal(JSON.stringify(health).includes(bad.user),false,'diagnostics contain no private identity');
  await c.query("UPDATE public.notification_center_organizations SET timezone='UTC' WHERE organization=$1",[bad.org]);
  await c.query('SELECT public.retry_notification_center_delivery($1,$2,$3)',[bad.org,id,bad.user]);
  await drain(c);assert.equal(await state(c,bad),1);
  await c.query('BEGIN');await c.query('SET LOCAL ROLE authenticated');
  await assert.rejects(c.query('SELECT public.get_notification_center_delivery_health()'),{code:'42501'});await c.query('ROLLBACK');
 }finally{await c.query('ROLLBACK');try{await cleanup(c,fs);}finally{await c.end();}}
});
test('tenant cursor rotates across calls with a one-recipient budget',async()=>{
 const c=await connect();const fs=[];
 try{
  const a=await fixture(c,5),b=await fixture(c,5);fs.push(a,b);
  await c.query('SELECT public.project_notification_center(1)');
  await c.query('SELECT public.project_notification_center(1)');
  assert.equal(await state(c,a),1);assert.equal(await state(c,b),1);
 }finally{try{await cleanup(c,fs);}finally{await c.end();}}
});
test('global lease and source-row lock serialize competing workers and a new attention revision',async()=>{
 const c=await connect(),first=await connect(),second=await connect();const fs=[];
 try{
  const f=await fixture(c);fs.push(f);
  const {rows:[{id}]}=await c.query('SELECT id FROM public.notification_center_events WHERE organization=$1',[f.org]);
  await first.query('BEGIN');assert.equal((await first.query('SELECT public.project_notification_center(100) n')).rows[0].n,1);
  assert.equal((await second.query('SELECT public.project_notification_center(100) n')).rows[0].n,0,'second worker cannot share the lease');
  await second.query('BEGIN');
  const pid=(await second.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const revision=second.query('UPDATE public.notification_center_events SET attention_revision=2 WHERE id=$1',[id]);
  let blocked=false;
  for(let i=0;i<100;i++){
   if((await c.query('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked){blocked=true;break;}
   await new Promise(resolve=>setTimeout(resolve,5));
  }
  assert.ok(blocked,'producer really meets the worker event lock');
  await first.query('COMMIT');await revision;
  await second.query('SELECT public.notification_center_capture_recipients_internal($1,NULL)',[id]);await second.query('COMMIT');
  await drain(c);assert.equal(await state(c,f),2);
  const {rows:[r]}=await c.query('SELECT processed_revision::int,eligible_revision::int FROM public.notification_center_recipients WHERE event_id=$1',[id]);
  assert.deepEqual(r,{processed_revision:2,eligible_revision:2});
  assert.equal((await c.query('SELECT count(*)::int n FROM public.notification_center_deliveries WHERE event_id=$1',[id])).rows[0].n,2);
 }finally{
  await Promise.all([first.query('ROLLBACK'),second.query('ROLLBACK')]);
  try{await cleanup(c,fs);}finally{await Promise.all([c.end(),first.end(),second.end()]);}
 }
});
test('a revision without eligible recipients completes at its publication boundary',async()=>{
 const c=await connect();const fs=[];
 try{
  const f=await fixture(c);fs.push(f);await drain(c);
  await c.query('UPDATE public.occasion_users SET is_editor_order_view=false WHERE occasion=$1',[f.oc]);
  const {rows:[{id}]}=await c.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','no-recipient') id",[f.org,f.oc]);
  const {rows:[r]}=await c.query('SELECT projected_revision::int,attention_revision::int FROM public.notification_center_events WHERE id=$1',[id]);
  assert.deepEqual(r,{projected_revision:1,attention_revision:1});
 }finally{try{await cleanup(c,fs);}finally{await c.end();}}
});
test('quarantine belongs to one revision and cannot suppress a later corrected source revision',async()=>{
 const c=await connect();const fs=[];
 try{
  const f=await fixture(c);fs.push(f);
  const {rows:[{id}]}=await c.query('SELECT id FROM public.notification_center_events WHERE organization=$1',[f.org]);
  await c.query("UPDATE public.notification_center_organizations SET timezone='invalid-zone' WHERE organization=$1",[f.org]);
  for(let i=0;i<5;i++){
   await c.query("UPDATE public.notification_center_recipients SET next_attempt_at='-infinity' WHERE event_id=$1",[id]);
   await c.query('SELECT public.project_notification_center(100)');
  }
  assert.equal((await c.query('SELECT quarantined FROM public.notification_center_recipients WHERE event_id=$1',[id])).rows[0].quarantined,true);
  await c.query("UPDATE public.notification_center_organizations SET timezone='UTC' WHERE organization=$1",[f.org]);
  await c.query('BEGIN');await c.query('UPDATE public.notification_center_events SET attention_revision=2 WHERE id=$1',[id]);
  await c.query('SELECT public.notification_center_capture_recipients_internal($1,NULL)',[id]);await c.query('COMMIT');
  await drain(c);assert.equal(await state(c,f),1,'only the corrected new revision allocates a delivery');
  const {rows:[r]}=await c.query('SELECT processed_revision::int,retry_revision::int,retry_count,quarantined FROM public.notification_center_recipients WHERE event_id=$1',[id]);
  assert.deepEqual(r,{processed_revision:2,retry_revision:2,retry_count:0,quarantined:false});
 }finally{await c.query('ROLLBACK');try{await cleanup(c,fs);}finally{await c.end();}}
});
