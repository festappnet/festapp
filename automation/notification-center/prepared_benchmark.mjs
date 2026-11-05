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
const receipt=process.env.NOTIFICATION_BENCH_RESUME==='1'?JSON.parse(readFileSync(output,'utf8')):{at:new Date().toISOString(),machine:{platform:platform(),arch:arch(),cpu:cpus()[0].model,cpuCount:cpus().length},postgres:(await c.query('SELECT version() version')).rows[0].version,workloads:[]};
const previousSchema=receipt.preparedSha256;
for(const row of receipt.workloads)row.schemaSha256??=previousSchema;
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
async function measure(f){
 const before=(await c.query('SELECT pg_current_wal_insert_lsn() lsn')).rows[0].lsn;
 const deliveryStart=performance.now();
 const delivery=await drain(c,{maxCalls:10000,maxMilliseconds:600000});
 // An idle/deferred pass is not proof that the durable queue is empty.
 while(Number((await c.query('SELECT count(*) n FROM public.notification_center_deliveries WHERE organization=$1',[f.org])).rows[0].n)<f.events*f.recipients){
  if(performance.now()-deliveryStart>1200000)throw Error('Delivery readiness deadline');
  await new Promise(resolve=>setTimeout(resolve,25));
  const part=await drain(c,{maxCalls:10000,maxMilliseconds:600000});
  for(const key of ['processed','prepared','repairedViews','calls'])delivery[key]+=part[key];
 }
 delivery.elapsedMs=performance.now()-deliveryStart;
 const deliveryWal=Number((await c.query('SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),$1) n',[before])).rows[0].n);
 const stats=(await c.query(`SELECT count(*)::int deliveries,extract(epoch FROM max(d.delivered_at)-min(e.occurred_at))*1000 eventAgeMs,
 percentile_cont(0.95) WITHIN GROUP(ORDER BY extract(epoch FROM d.delivered_at-r.pending_since)*1000) deliveryWaitP95Ms,
 max(extract(epoch FROM d.delivered_at-r.pending_since)*1000) deliveryWaitMaxMs
 FROM public.notification_center_deliveries d JOIN public.notification_center_events e ON e.id=d.event_id
 JOIN public.notification_center_recipients r ON r.event_id=d.event_id AND r.recipient=d.recipient WHERE d.organization=$1`,[f.org])).rows[0];
 assertEqual(stats.deliveries,f.events*f.recipients,'all recipient work drains');
 await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[f.users[0]]);
 let preparation={calls:0,elapsedMs:0,prepared:0};
 const preparationStart=performance.now();
 const preparationWalStart=(await c.query('SELECT pg_current_wal_insert_lsn() lsn')).rows[0].lsn;
 let initial=(await c.query('SELECT public.get_notification_center_view($1,$2) result',[f.org,f.oc])).rows[0].result;
 while(initial.state==='preparing'){
  const part=await drain(c,{maxCalls:10000,maxMilliseconds:600000});
  preparation.calls+=part.calls;preparation.prepared+=part.prepared;
  if(performance.now()-preparationStart>1200000)throw Error('Backfill readiness deadline');
  initial=(await c.query('SELECT public.get_notification_center_view($1,$2) result',[f.org,f.oc])).rows[0].result;
 }
 preparation.elapsedMs=performance.now()-preparationStart;
 preparation.walBytes=Number((await c.query('SELECT pg_wal_lsn_diff(pg_current_wal_insert_lsn(),$1) n',[preparationWalStart])).rows[0].n);
 await c.query("SELECT public.get_notification_center_view($1,$2,p_mode=>'close',p_view=>$3)",[f.org,f.oc,initial.viewToken]);
 const samples=[];let returned;
 for(let i=0;i<(21);i++){
  try {
   const {r,ms}=await timed("SELECT public.get_notification_center_view($1,$2) result",[f.org,f.oc]);
   returned=r.rows[0].result;
   if(returned.state==='preparing'){
    await drain(c,{maxCalls:10000,maxMilliseconds:600000});i--;continue;
   }
   assertEqual(returned.state,'ready','modern ready state');samples.push(ms);
   await c.query("SELECT public.get_notification_center_view($1,$2,p_mode=>'close',p_view=>$3)",[f.org,f.oc,returned.viewToken]);
  } catch(error) {
   if(error.code!=='57014')throw error;
   receipt.workloads.push({events:f.events,recipients:f.recipients,totalDeliveries:stats.deliveries,publicationMs:f.publicationMs,publicationWalBytes:f.publicationWal,delivery,deliveryWalBytes:deliveryWal,...stats,overview:{timeoutMs:120000,completedSamples:samples.length,sqlstate:error.code}});
   writeFileSync(output,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(receipt.workloads.at(-1)));return;
  }
 }
 assertEqual(returned.items[0].data.activityCount,f.events,'full nonempty distinct-order batch');
 const storage=(await c.query(`SELECT pg_total_relation_size('public.notification_center_deliveries') deliveries_bytes,
 pg_total_relation_size('public.notification_center_recipients') recipients_bytes`)).rows[0];
 const row={schemaSha256:receipt.preparedSha256,events:f.events,recipients:f.recipients,personalHistory:f.events,totalDeliveries:stats.deliveries,
 publicationMs:f.publicationMs,publicationWalBytes:f.publicationWal,delivery,deliveryWalBytes:deliveryWal,preparation,...stats,
 preparedOpen:{samples:samples.length-1,firstSampleMs:samples[0],p50Ms:percentile(samples.slice(1),.5),p95Ms:percentile(samples.slice(1),.95),p99Ms:percentile(samples.slice(1),.99),rows:returned.items.length},storageWholeRelations:storage};
 receipt.workloads.push(row);writeFileSync(output,JSON.stringify(receipt,null,2)+'\n');console.log(JSON.stringify(row));
}
function assertEqual(a,b,why){if(a!==b)throw Error(`${why}: ${a} !== ${b}`);}
async function cleanup(f){
 await c.query('DELETE FROM public.notification_center_events WHERE organization=$1',[f.org]);
 await c.query('DELETE FROM eshop.orders WHERE occasion=$1',[f.oc]);
 await c.query('DELETE FROM public.occasion_users WHERE occasion=$1',[f.oc]);
 await c.query('DELETE FROM public.occasions WHERE id=$1',[f.oc]);
 await c.query('DELETE FROM public.user_info WHERE id=ANY($1::uuid[])',[f.users]);
 await c.query('DELETE FROM public.organizations WHERE id=$1',[f.org]);
 await c.query('DELETE FROM auth.users WHERE id=ANY($1::uuid[])',[f.users]);
}
try{
 // Same personal-history scale with distinct customers, then independent fanout.
 for(const [events,recipients] of [[1000,1],[10000,1],[100000,1],[1000,5],[1000,20]]){
  if(receipt.workloads.some(row=>row.events===events&&row.recipients===recipients))continue;
  const f=await setup(events,recipients);await measure(f);await cleanup(f);fixtures.splice(fixtures.indexOf(f),1);
 }
}finally{
 // Cleanup only this run's explicitly recorded disposable fixtures.
 try{for(const f of fixtures)if(f.oc)await cleanup(f);}finally{await c.end();}
}
