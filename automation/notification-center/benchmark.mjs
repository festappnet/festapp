#!/usr/bin/env node
// Disposable SQL timings, not browser click-to-content or production capacity.
import {randomUUID} from 'node:crypto';
import {writeFileSync,readFileSync} from '../lib/migration_inputs.mjs';
import {createHash} from 'node:crypto';
import {cpus,platform,arch} from 'node:os';
import {drain} from './drain.mjs';
import {withDatabase,receiptPath,setupFixture,cleanupFixture,timed as measureQuery,percentile,assertEqual} from './benchmark_support.mjs';
const output=receiptPath(process.argv[2],process.env.NOTIFICATION_BENCH_RESUME==='1');
await withDatabase(async([c],fixtures)=>{
const timed=(q,p)=>measureQuery(c,q,p);
const receipt=process.env.NOTIFICATION_BENCH_RESUME==='1'?JSON.parse(readFileSync(output,'utf8')):{at:new Date().toISOString(),machine:{platform:platform(),arch:arch(),cpu:cpus()[0].model,cpuCount:cpus().length},postgres:(await c.query('SELECT version() version')).rows[0].version,workloads:[]};
const previousSchema=receipt.preparedSha256;
for(const row of receipt.workloads)row.schemaSha256??=previousSchema;
receipt.preparedSha256=createHash('sha256').update(readFileSync(new URL('../../supabase/migrations/20261105120000_notification_center_prepared_views.sql',import.meta.url))).digest('hex');
receipt.projectorSha256=createHash('sha256').update(readFileSync(new URL('../../database/functions/notification_center/core.sql',import.meta.url))).digest('hex');
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
{
 // Same personal-history scale with distinct customers, then independent fanout.
 for(const [events,recipients] of (process.env.NOTIFICATION_BENCH_SMOKE==='1'?[[3,1]]:[[1000,1],[10000,1],[100000,1],[1000,5],[1000,20]])){
  if(receipt.workloads.some(row=>row.events===events&&row.recipients===recipients))continue;
  const f=await setupFixture(c,fixtures,events,recipients);await measure(f);await cleanupFixture(c,f);fixtures.splice(fixtures.indexOf(f),1);
 }
 }
});
