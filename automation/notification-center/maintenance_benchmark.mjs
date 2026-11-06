#!/usr/bin/env node
// Disposable SQL timings, not browser click-to-content or production capacity.
import {randomUUID} from 'node:crypto';
import {writeFileSync,readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {cpus,platform,arch} from 'node:os';
import {drain} from './drain.mjs';
import {withDatabase,receiptPath,setupFixture,cleanupFixture,timed as measureQuery,percentile,assertEqual} from './benchmark_support.mjs';
const output=receiptPath(process.argv[2],true);
await withDatabase(async([c],fixtures)=>{
const timed=(q,p)=>measureQuery(c,q,p);
const receipt={at:new Date().toISOString(),machine:{platform:platform(),arch:arch(),cpu:cpus()[0].model,cpuCount:cpus().length},postgres:(await c.query('SELECT version() version')).rows[0].version,workloads:[]};
receipt.preparedSha256=createHash('sha256').update(readFileSync(new URL('../../supabase/migrations/20261105120000_notification_center_prepared_views.sql',import.meta.url))).digest('hex');
receipt.projectorSha256=createHash('sha256').update(readFileSync(new URL('../../database/functions/notification_center/core.sql',import.meta.url))).digest('hex');
const f=await setupFixture(c,fixtures,1000,5);
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
{
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
 v=await open('refresh',token);assertEqual(v.items[0].data.activityCount,999,'hidden membership preserves authorized order totals');
 const replay=await phase('idempotent completed work replay',async()=>{});
 const group='occasion-kind:'+f.oc+':order_created';
 const reads=await phase('29 prefix receipts and compacted history repair',async()=>{
  const cuts=(await c.query('SELECT sequence FROM public.notification_center_view_members WHERE organization=$1 AND recipient=$2 AND eligible ORDER BY sequence LIMIT 29',[f.org,f.users[0]])).rows;
  let after=0;for(const cut of cuts){await c.query('SELECT public.notification_center_prepared_record_read($1,$2,$3,$4,true)',[f.org,group,after,cut.sequence]);after=cut.sequence;}
 });
 const samples=[];let page;
 for(let i=0;i<21;i++){
  const start=performance.now();page=await open();samples.push(performance.now()-start);
  assertEqual(page.state,'ready','thirty batches ready');assertEqual(page.items.length,2,'one compacted read history and one unread batch');
  await open('close',page.viewToken);
 }
 const plan=(await c.query(`EXPLAIN(ANALYZE,BUFFERS,FORMAT JSON) SELECT id,latest_at FROM public.notification_center_summary_scopes
 WHERE organization=$1 AND recipient=$2 AND scope=$3 ORDER BY latest_at DESC,id DESC LIMIT 101`,[f.org,f.users[0],'orders:'+f.oc])).rows[0]['QUERY PLAN'];
 const payloadStorage=(await c.query(`SELECT
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_view_members t WHERE organization=$1) member_tuple_payload_bytes,
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_batch_summaries t WHERE organization=$1) summary_tuple_payload_bytes,
 (SELECT sum(pg_column_size(t)) FROM public.notification_center_view_rows t JOIN public.notification_center_views v ON v.token=t.token WHERE v.organization=$1) view_tuple_payload_bytes`,[f.org])).rows[0];
 const target=JSON.parse(readFileSync(output,'utf8'));
 target.preparedMaintenance={events:1000,recipients:5,activeDelivery,cancelled,privacy,replay,reads,compactedRows:{rows:2,samples:20,firstSampleMs:samples[0],p50Ms:percentile(samples.slice(1),.5),p95Ms:percentile(samples.slice(1),.95),p99Ms:percentile(samples.slice(1),.99)},payloadStorage,plan};
 writeFileSync(output,JSON.stringify(target,null,2)+'\n');console.log(JSON.stringify({...target.preparedMaintenance,plan:undefined}));
}
});
