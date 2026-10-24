import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
if(!connectionString || new URL(connectionString).hostname!=='127.0.0.1' || !['55432','57732'].includes(new URL(connectionString).port)) throw Error('Disposable local DB required');
async function connect(){const c=new Client({connectionString});await c.connect();await c.query("SET statement_timeout='10s'");return c;}
async function fixture(c){
 const user=randomUUID();await c.query('INSERT INTO auth.users(id) VALUES($1)',[user]);
 const {rows:[org]}=await c.query("INSERT INTO public.organizations(title) VALUES('Read cursor concurrency') RETURNING id");
 await c.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[user,org.id]);
 const {rows:[oc]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Concurrent',$2,now(),now()+interval '1 day') RETURNING id",[org.id,randomUUID()]);
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) VALUES($1,$2,true)',[oc.id,user]);
 await c.query('INSERT INTO public.notification_center_organizations(organization) VALUES($1)',[org.id]);
 await c.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','first')",[org.id,oc.id]);
 await c.query('SELECT public.project_notification_center(500)');
 return {user,org:org.id,oc:oc.id};
}
async function actor(c,f){await c.query('BEGIN');await c.query("SELECT set_config('request.jwt.claim.sub',$1,true)",[f.user]);await c.query('SET LOCAL ROLE authenticated');}
async function blocked(c,pid){
 for(let i=0;i<100;i++){
  if((await c.query('SELECT cardinality(pg_blocking_pids($1))>0 blocked',[pid])).rows[0].blocked)return;
  await new Promise(r=>setTimeout(r,10));
 }
 throw Error('Expected genuine Postgres lock contention');
}
test('delivery after open snapshot remains unread and commits its sequence atomically',async()=>{
 const setup=await connect(),reader=await connect(),writer=await connect();
 try{
  const f=await fixture(setup);await actor(reader,f);
  const opened=(await reader.query('SELECT public.open_notification_center($1) result',[f.org])).rows[0].result;
  assert.equal(opened.snapshot,1);
  await writer.query('BEGIN');
  await writer.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','second')",[f.org,f.oc]);
  const pid=(await writer.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const pending=writer.query('SELECT public.project_notification_center(500)');
  await blocked(setup,pid);await reader.query('COMMIT');await pending;await writer.query('COMMIT');
  await actor(reader,f);
  const badge=(await reader.query('SELECT public.get_notification_center_badge($1) result',[f.org])).rows[0].result;
  assert.deepEqual({unread:badge.unread,last:badge.lastSequence,read:badge.readThrough},{unread:true,last:2,read:1});
  await reader.query('COMMIT');
 }finally{for(const c of [reader,writer]){await c.query('ROLLBACK');await c.end();}await setup.end();}
});
test('open waits for an uncommitted delivery; two opens never lower the watermark',async()=>{
 const setup=await connect(),a=await connect(),b=await connect();
 try{
  const f=await fixture(setup);
  await setup.query('BEGIN');
  await setup.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','second')",[f.org,f.oc]);
  await setup.query('SELECT public.project_notification_center(500)');
  await actor(a,f);const pid=(await a.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const first=a.query('SELECT public.open_notification_center($1) result',[f.org]);
  await blocked(b,pid);await setup.query('COMMIT');assert.equal((await first).rows[0].result.readThrough,2);
  await actor(b,f);const pidB=(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const second=b.query('SELECT public.open_notification_center($1) result',[f.org]);
  await blocked(setup,pidB);await a.query('COMMIT');assert.equal((await second).rows[0].result.readThrough,2);await b.query('COMMIT');
 }finally{for(const c of [setup,a,b]){await c.query('ROLLBACK');await c.end();}}
});
test('initialization serializes with producers even before the collection row exists',async()=>{
 const setup=await connect(),activation=await connect(),producer=await connect();
 try{
  const f=await fixture(setup);await setup.query('DELETE FROM public.notification_center_organizations WHERE organization=$1',[f.org]);
  await producer.query('BEGIN');
  await producer.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','before-activation')",[f.org,f.oc]);
  await activation.query('BEGIN');const pid=(await activation.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const turningOn=activation.query('SELECT public.initialize_notification_center_internal($1)',[f.org]);
  await blocked(setup,pid);await producer.query('COMMIT');await turningOn;
  // The activation transaction still owns the gate; a concurrent producer must wait.
  await producer.query('BEGIN');const pidP=(await producer.query('SELECT pg_backend_pid() pid')).rows[0].pid;
  const publishing=producer.query("SELECT public.notification_center_publish_internal($1,$2,'order_created','after-activation')",[f.org,f.oc]);
  await blocked(setup,pidP);await activation.query('COMMIT');await publishing;await producer.query('COMMIT');
  const {rows:[r]}=await setup.query(`SELECT
   count(*) FILTER(WHERE source_key='before-activation')::int before,
   count(*) FILTER(WHERE source_key='after-activation' AND occurred_at>=a.initialized_at)::int after
   FROM public.notification_center_events e JOIN public.notification_center_organizations a ON a.organization=e.organization WHERE e.organization=$1`,[f.org]);
  assert.deepEqual(r,{before:0,after:1});
 }finally{for(const c of [setup,activation,producer]){await c.query('ROLLBACK');await c.end();}}
});
test('a later capacity impact refreshes verified author eligibility instead of retaining old self-suppression',async()=>{
 const c=await connect();
 try{
  const f=await fixture(c), second=randomUUID();
  await c.query('UPDATE public.occasion_users SET is_editor_order=true WHERE occasion=$1 AND "user"=$2',[f.oc,f.user]);
  await c.query('INSERT INTO auth.users(id) VALUES($1)',[second]);
  await c.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[second,f.org]);
  await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor_order) VALUES($1,$2,true,true)',[f.oc,second]);
  const observe=(remaining,actor)=>c.query(`SELECT public.notification_center_capacity_transition_internal($1,$2,'actor-capacity',jsonb_build_object('limit',10,'remainingPublic',$3::int),$4)`,[f.org,f.oc,remaining,actor]);
  await observe(2,f.user);await observe(1,f.user);
  await c.query('SELECT public.project_notification_center(500)');
  let {rows:[r]}=await c.query("SELECT count(*)::int n FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id WHERE e.organization=$1 AND e.source_key='actor-capacity:episode:1' AND d.recipient=$2",[f.org,f.user]);
  assert.equal(r.n,0,'initial warning hides the verified author');
  await observe(0,second);await c.query('SELECT public.project_notification_center(500)');
  ({rows:[r]}=await c.query(`SELECT count(*) FILTER(WHERE d.recipient=$2)::int original_author,count(*) FILTER(WHERE d.recipient=$3 AND d.attention_revision=2)::int current_author
   FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id WHERE e.organization=$1 AND e.source_key='actor-capacity:episode:1'`,[f.org,f.user,second]));
  assert.deepEqual(r,{original_author:1,current_author:0});
 }finally{await c.end();}
});
