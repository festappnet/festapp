#!/usr/bin/env node
// Disposable SQL timings, not browser click-to-content or production capacity.
import {createRequire} from 'node:module';
import {randomUUID} from 'node:crypto';
import {writeFileSync,readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {cpus,platform,arch} from 'node:os';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
import {drain} from './drain.mjs';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;assertLocalDatabaseUrl(connectionString);
const c=new Client({connectionString,application_name:'notification-scalability-benchmark'});await c.connect();
await assertDisposableDatabase(c);
await c.query("SET statement_timeout='120s'; SET lock_timeout='2s'");
const output=process.argv[2];if(!output)throw Error('Receipt file path required');
const receipt={at:new Date().toISOString(),machine:{platform:platform(),arch:arch(),cpu:cpus()[0].model,cpuCount:cpus().length},postgres:(await c.query('SELECT version() version')).rows[0].version,workloads:[]};
receipt.preparedSha256=createHash('sha256').update(readFileSync(new URL('../../supabase/migrations/20261105120000_notification_center_prepared_views.sql',import.meta.url))).digest('hex');
receipt.projectorSha256=createHash('sha256').update(readFileSync(new URL('../../database/functions/notification_center/core.sql',import.meta.url))).digest('hex');
const fixtures=[];
function percentile(xs,p){return [...xs].sort((a,b)=>a-b)[Math.min(xs.length-1,Math.ceil(xs.length*p)-1)];}
async function timed(query,params){const t=performance.now();const r=await c.query(query,params);return {r,ms:performance.now()-t};}
async function setup(events,recipients){
 const {rows:[{id:org}]}=await c.query("INSERT INTO public.organizations(title) VALUES('Notification scalability benchmark') RETURNING id");
 const users=Array.from({length:recipients},()=>randomUUID());const f={org,users};fixtures.push(f);
 await c.query('INSERT INTO auth.users(id) SELECT unnest($1::uuid[])',[users]);
 await c.query("INSERT INTO public.user_info(id,organization,email_readonly) SELECT u,$2,'viewer-'||u||'@example.invalid' FROM unnest($1::uuid[]) u",[users,org]);
 const {rows:[{id:oc}]}=await c.query("INSERT INTO public.occasions(organization,title,link,start_time,end_time) VALUES($1,'Measured orders',$2,now(),now()+interval '1 day') RETURNING id",[org,randomUUID()]);f.oc=oc;
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view) SELECT $1,unnest($2::uuid[]),true',[oc,users]);
 await c.query("INSERT INTO public.notification_center_organizations(organization,initialized_at) VALUES($1,now()-interval '60 days')",[org]);
 await c.query(`INSERT INTO eshop.orders(occasion,state,order_symbol,order_sequence,data)
 SELECT $1,'ordered',public.generate_order_symbol(),i,jsonb_build_object('name','Buyer '||i,'email','buyer'||i||'@example.invalid') FROM generate_series(1,$2::int) i`,[oc,events]);
 const before=(await c.query('SELECT pg_current_wal_insert_lsn() lsn')).rows[0].lsn;
 const publication=await timed(`SELECT public.notification_center_publish_internal($1,$2,'order_created','bench:'||o.id,
 jsonb_build_object('orderId',o.id,'count',CASE WHEN o.order_sequence%10=0 THEN NULL ELSE o.order_sequence%3+1 END,
 'formContext',jsonb_build_object('allowsMultiple',true)),NULL,now()-interval '1 day')
 FROM eshop.orders o WHERE o.occasion=$2`,[org,oc]);
 const publicationWal=Number((await c.query('SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),$1) n',[before])).rows[0].n);
 return Object.assign(f,{events,recipients,publicationMs:publication.ms,publicationWal});
}
function assertEqual(a,b,why){if(a!==b)throw Error(`${why}: ${a} !== ${b}`);}
async function cleanup(f){
 await c.query('DELETE FROM public.notification_center_events WHERE organization=$1',[f.org]);
 await c.query('DELETE FROM eshop.orders WHERE occasion=$1',[f.oc]);
 await c.query('DELETE FROM public.occasion_users WHERE occasion=$1',[f.oc]);
 await c.query('DELETE FROM public.occasions WHERE id=$1',[f.oc]);
 await c.query('DELETE FROM public.organization_users WHERE organization=$1',[f.org]);
 await c.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])',[f.users]);
 await c.query('DELETE FROM public.organizations WHERE id=$1',[f.org]);
 await c.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])',[f.users]);
}

const f=await setup(1000,5);
async function phase(name,action){
 const start=performance.now(),lsn=(await c.query('SELECT pg_current_wal_insert_lsn() lsn')).rows[0].lsn;
 await action();
 const work=await drain(c,{maxCalls:10000,maxMilliseconds:120000});
 for(let i=0;i<100;i++){
  const pending=Number((await c.query(`SELECT count(*) n FROM public.notification_center_projection_scopes s JOIN public.notification_center_user_state u USING(organization,recipient)
   WHERE s.organization=$1 AND (s.phase<>'ready' OR s.pending_delivery>0 OR s.pending_events>0 OR s.pending_groups>0 OR s.privacy_pending OR s.prepared_sequence<u.last_delivery_sequence)`,[f.org])).rows[0].n);
  const dirty=Number((await c.query(`SELECT count(*) n FROM public.notification_center_view_rows r JOIN public.notification_center_views v ON v.token=r.token
   JOIN public.notification_center_projection_scopes s USING(organization,recipient) JOIN public.notification_center_user_state u USING(organization,recipient)
   WHERE v.organization=$1 AND (r.state='preparing' OR r.revision<>s.revision OR r.read_revision<>u.view_read_revision OR r.privacy_key<>md5(s.privacy::text))`,[f.org])).rows[0].n);
  if(!pending&&!dirty)break;
  if(i===99)throw Error('Maintenance readiness deadline');
  await new Promise(resolve=>setTimeout(resolve,25));
  const part=await drain(c,{maxCalls:10000,maxMilliseconds:120000});
  for(const key of ['processed','prepared','repairedViews','calls'])work[key]+=part[key];
 }
 return {name,elapsedMs:performance.now()-start,work,walBytes:Number((await c.query('SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),$1) n',[lsn])).rows[0].n)};
}
async function open(mode='open',token=null){return (await c.query('SELECT public.get_notification_center_view($1,$2,p_mode=>$3,p_view=>$4) result',[f.org,f.oc,mode,token])).rows[0].result;}
try{
 for(const user of f.users){await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[user]);await c.query('SELECT public.get_notification_center_prepared_badge($1)',[f.org]);}
 for(let i=0;i<10;i++)await c.query('SELECT public.prepare_notification_center(100)');
 const activeDelivery=await phase('delivery with five maintained projections',async()=>{});
 await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[f.users[0]]);
 let v=await open();
 for(let i=0;v.state==='preparing'&&i<30;i++){await drain(c,{maxCalls:10000,maxMilliseconds:120000});await new Promise(resolve=>setTimeout(resolve,25));v=await open();}
 if(v.state!=='ready')console.log(JSON.stringify({response:v,scopes:(await c.query('SELECT phase,delivery_initialized,pending_delivery,pending_events,pending_groups,privacy_pending,prepared_sequence,applied_read_revision,privacy FROM public.notification_center_projection_scopes WHERE organization=$1',[f.org])).rows}));
 assertEqual(v.state,'ready','prewarmed recipient ready');assertEqual(v.items[0].data.activityCount,1000,'all maintained contributions');
 const token=v.viewToken;
 const cancelled=await phase('cancel one source and repair retained view',async()=>{
  const {rows:[o]}=await c.query('SELECT id FROM eshop.orders WHERE occasion=$1 ORDER BY order_sequence LIMIT 1',[f.oc]);
  await c.query("UPDATE eshop.orders SET state='storno' WHERE id=$1",[o.id]);
  await c.query('SELECT public.notification_center_order_state_internal($1)',[o.id]);
  assertEqual((await open('refresh',token)).state,'preparing','storno redacts retained payload');
 });
 v=await open('refresh',token);assertEqual(v.items[0].data.activityCount,999,'storno retracts one');
 const hidden=randomUUID();f.users.push(hidden);
 await c.query('INSERT INTO auth.users(id) VALUES($1)',[hidden]);
 await c.query("INSERT INTO public.user_info(id,organization,email_readonly) VALUES($1,$2,'buyer2@example.invalid')",[hidden,f.org]);
 const privacy=await phase('hide one contact and repair retained view',async()=>{
  await c.query('INSERT INTO public.organization_users(organization,"user",is_hidden) VALUES($1,$2,true)',[f.org,hidden]);
  assertEqual((await open('refresh',token)).state,'preparing','hidden delta redacts retained payload');
 });
 v=await open('refresh',token);assertEqual(v.items[0].data.activityCount,998,'hide retracts one');
 const replay=await phase('idempotent completed work replay',async()=>{});
 const group='occasion-kind:'+f.oc+':order_created';
 const reads=await phase('29 prefix receipts and group repair',async()=>{
  const cuts=(await c.query('SELECT sequence FROM public.notification_center_view_members WHERE organization=$1 AND recipient=$2 AND eligible ORDER BY sequence LIMIT 29',[f.org,f.users[0]])).rows;
  let after=0;for(const cut of cuts){await c.query('SELECT public.notification_center_prepared_record_read($1,$2,$3,$4,true)',[f.org,group,after,cut.sequence]);after=cut.sequence;}
 });
 const samples=[];let page;
 for(let i=0;i<21;i++){
  const start=performance.now();page=await open();samples.push(performance.now()-start);
  assertEqual(page.state,'ready','thirty batches ready');assertEqual(page.items.length,30,'thirty nonempty batches');
  await open('close',page.viewToken);
 }
 const plan=(await c.query(`EXPLAIN(ANALYZE,BUFFERS,FORMAT JSON) SELECT id,latest_at FROM public.notification_center_summary_scopes
 WHERE organization=$1 AND recipient=$2 AND scope=$3 ORDER BY latest_at DESC,id DESC LIMIT 101`,[f.org,f.users[0],'orders:'+f.oc])).rows[0]['QUERY PLAN'];
 const payloadStorage=(await c.query(`SELECT
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_view_members t WHERE organization=$1) member_tuple_payload_bytes,
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_batch_summaries t WHERE organization=$1) summary_tuple_payload_bytes,
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_view_rows t JOIN public.notification_center_views v ON v.token=t.token WHERE v.organization=$1) view_tuple_payload_bytes`,[f.org])).rows[0];
 const target=JSON.parse(readFileSync(output,'utf8'));
 target.preparedMaintenance={events:1000,recipients:5,activeDelivery,cancelled,privacy,replay,reads,thirtyRows:{samples:20,firstSampleMs:samples[0],p50Ms:percentile(samples.slice(1),.5),p95Ms:percentile(samples.slice(1),.95),p99Ms:percentile(samples.slice(1),.99)},payloadStorage,plan};
 writeFileSync(output,JSON.stringify(target,null,2)+'\n');console.log(JSON.stringify({...target.preparedMaintenance,plan:undefined}));
}finally{try{await cleanup(f);}finally{await c.end();}}
