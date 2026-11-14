// Read-only with respect to retained application state: all fixtures, function
// variants and successful checkouts are inside one outer transaction, rolled back.
// Run only on the explicitly marked task-owned local webhook database.
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { writeFile } from 'node:fs/promises';
import { platform, arch } from 'node:os';
import { fixture, input } from '../../tools/festapp/test/form-completion-fixtures.mjs';
const connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
assert(connection,'FESTAPP_MCP_TEST_DATABASE_URL is required');
assert.match(process.env.FESTAPP_LOCAL_DB_PROJECT_ID??'',/^festapp-webhooks-/);
assert.equal(new URL(connection).hostname,'127.0.0.1');
assert(!['55432','61022','61032'].includes(new URL(connection).port),'Use a task-owned project');
const cleanup=[];
const s=await fixture({after:fn=>cleanup.push(fn)}),{db,f,made}=s;
const percentile=(values,p)=>values.toSorted((a,b)=>a-b)[Math.min(values.length-1,Math.floor(values.length*p))];
const summarize=values=>({samples:values.length,medianMs:percentile(values,.5),p95Ms:percentile(values,.95),minMs:Math.min(...values),maxMs:Math.max(...values)});
const outcomes=[];let receipt;
try{
 await db.query("SET LOCAL statement_timeout='15s'");
 await db.query('update forms set is_open=true where id=$1',[made.formId]);
 await db.query('update eshop.products set price=100 where id=$1',[made.authoring.products[0].id]);
 const formKey=(await db.query('select key from forms where id=$1',[made.formId])).rows[0].key;
 const otherForm=Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Benchmark other form',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id",[f.occasion])).rows[0].id);
 const subscriptions=[];
 for(let i=0;i<11;i++){
  const sid=randomUUID();subscriptions.push(sid);
  await db.query('select integration_webhook_api_v1($1,$2,$3,$4,\'create\',$5)',[f.occasion,f.org,f.unit,(i===10?'b':'a').repeat(64),{subscriptionId:sid,commandId:randomUUID(),formId:i===10?otherForm:made.formId,expiresAt:new Date(Date.now()+86400000).toISOString()}]);
 }
 const original=(await db.query("select pg_get_functiondef('public.create_ticket_order_internal_v1(jsonb)'::regprocedure) definition")).rows[0].definition;
 const baseline=original.replace(/\n\s*PERFORM public\.emit_order_webhook_internal\(target\);/,'');
 assert.notEqual(original,baseline,'Canonical producer hook must be found exactly');
 assert(!baseline.includes('emit_order_webhook_internal'));
 const cases=[
  {id:'before_webhooks',hook:false,active:1,backlog:0,deliveries:0},
  {id:'no_active_subscription',hook:true,active:0,backlog:0,deliveries:0},
  {id:'other_form_only',hook:true,active:0,other:true,backlog:0,deliveries:0},
  {id:'one_matching',hook:true,active:1,backlog:0,deliveries:1},
  {id:'ten_matching',hook:true,active:10,backlog:0,deliveries:10},
  {id:'before_webhooks_backlog_10000',hook:false,active:1,backlog:10000,deliveries:0},
  {id:'one_matching_backlog_10000',hook:true,active:1,backlog:10000,deliveries:1},
 ];
 const samples=Object.fromEntries(cases.map(c=>[c.id,[]]));
 const buffers=Object.fromEntries(cases.map(c=>[c.id,[]]));
 const blocks=Object.fromEntries(cases.map(c=>[c.id,[]]));
 async function measure(c,email){
  await db.query('SAVEPOINT measurement');
  try{
   await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");
   await db.query('SET LOCAL ROLE anon');
   const payload={...input(s,email),form:formKey,payment_method:'bank'};
   const result=await db.query(`EXPLAIN (ANALYZE,BUFFERS,WAL,FORMAT JSON) WITH created AS MATERIALIZED (
     SELECT create_ticket_order_client_sync_v1($1,$2,$3) response)
     SELECT CASE WHEN (response->>'code')::int=200 THEN response#>>'{data,order,id}'
       ELSE ('CHECKOUT_FAILED_'||coalesce(response->>'code','NULL')||'_'||coalesce(response#>>'{data,message}',''))::bigint::text END FROM created`,[payload,randomUUID(),randomUUID()]);
   const plan=result.rows[0]['QUERY PLAN'][0];
   await db.query('RESET ROLE');
   const check=(await db.query('select o.id,(select count(*) from integration_webhook_events e join integration_webhook_deliveries d on d.event=e.id where e.order_id=o.id) deliveries from eshop.orders o where o.form=$1',[made.formId])).rows;
   assert.equal(check.length,1,'Every timed call must create one real order');
   assert.equal(Number(check[0].deliveries),c.deliveries,'Fanout must match the selected event/form scope');
   return {ms:plan['Execution Time'],hits:plan.Plan['Shared Hit Blocks']??0,reads:plan.Plan['Shared Read Blocks']??0,walBytes:plan.Plan['WAL Bytes']??0};
  }finally{await db.query('ROLLBACK TO SAVEPOINT measurement');await db.query('RELEASE SAVEPOINT measurement');}
 }
 for(let block=0;block<6;block++){
  // Rotate scenario order across blocks to avoid a fixed warmup/time bias.
  const normal=cases.filter(c=>!c.backlog);
  const order=normal.map((_,i)=>normal[(i+block)%normal.length]);
  for(const c of order){
   await db.query(c.hook?original:baseline);
   await db.query("update integration_webhook_subscriptions set state='paused' where organization=$1",[f.org]);
   const active=[...subscriptions.slice(0,c.active),...(c.other?[subscriptions[10]]:[])];
   if(active.length)await db.query("update integration_webhook_subscriptions set state='active' where id=any($1::uuid[])",[active]);
   for(let warm=0;warm<3;warm++)await measure(c,'warm-'+randomUUID()+'@example.invalid');
   const timings=[];
   for(let i=0;i<12;i++){
    const value=await measure(c,`webhooks-bench-${block}-${i}@example.invalid`);
    samples[c.id].push(value.ms);timings.push(value.ms);buffers[c.id].push(value);
   }
   blocks[c.id].push(percentile(timings,.5));
  }
  process.stderr.write(`Benchmark block ${block+1}/6 complete\n`);
 }
 async function idlePoll(){
  const values=[];
  await db.query(original);
  await db.query("update integration_webhook_subscriptions set state='active' where id=$1",[subscriptions[1]]);
  for(let i=0;i<80;i++){
   const value=(await db.query(`EXPLAIN (ANALYZE,BUFFERS,FORMAT JSON) SELECT integration_webhook_api_v1($1,$2,$3,$4,'claim',$5)`,[f.occasion,f.org,f.unit,'a'.repeat(64),{subscriptionId:subscriptions[1]}])).rows[0]['QUERY PLAN'][0]['Execution Time'];
   if(i>=8)values.push(value);
  }
  return summarize(values);
 }
 const idleNormal=await idlePoll();
 await db.query("insert into integration_webhook_events(organization,occasion,event_type,body) select $1,$2,'net.festapp.webhook.test.v1','{}' from generate_series(1,10000)",[f.org,f.occasion]);
 await db.query('insert into integration_webhook_deliveries(subscription,event,state) select $1,id,\'pending\' from integration_webhook_events where organization=$2',[subscriptions[0],f.org]);
 await db.query("update integration_webhook_subscriptions set state='paused' where organization=$1",[f.org]);
 await db.query("update integration_webhook_subscriptions set state='active' where id=$1",[subscriptions[0]]);
 // Backlog fixture is inserted once, AFTER normal measurements. Never toggle
 // 10000 row states between timed arms, which would bias MVCC/index costs.
 const backlogCases=cases.filter(c=>c.backlog);
 for(let block=0;block<6;block++)for(const c of (block%2?backlogCases.toReversed():backlogCases)){
  await db.query(c.hook?original:baseline);
  for(let warm=0;warm<3;warm++)await measure(c,'warm-'+randomUUID()+'@example.invalid');
  const timings=[];
  for(let i=0;i<12;i++){
   const value=await measure(c,`webhooks-backlog-${block}-${i}@example.invalid`);
   samples[c.id].push(value.ms);timings.push(value.ms);buffers[c.id].push(value);
  }
  blocks[c.id].push(percentile(timings,.5));
 }
 const idleBacklog=await idlePoll();

 for(const c of cases){
  const stats=summarize(samples[c.id]);
  const referenceId=c.backlog?'before_webhooks_backlog_10000':'before_webhooks';
  const reference=percentile(samples[referenceId],.5);
  const paired=blocks[c.id].map((value,i)=>(value/blocks[referenceId][i]-1)*100);
  outcomes.push({...c,reference:referenceId,...stats,deltaMedianMs:stats.medianMs-reference,deltaMedianPct:(stats.medianMs/reference-1)*100,
   blockMedianDeltasPct:{median:percentile(paired,.5),min:Math.min(...paired),max:Math.max(...paired)},
   medianSharedHitBlocks:percentile(buffers[c.id].map(v=>v.hits),.5),totalSharedReads:buffers[c.id].reduce((n,v)=>n+v.reads,0),medianWalBytes:percentile(buffers[c.id].map(v=>v.walBytes),.5)});
 }
 receipt={measuredAt:new Date().toISOString(),environment:{platform:platform(),arch:arch(),node:process.version,postgres:(await db.query('select version() value')).rows[0].value,project:process.env.FESTAPP_LOCAL_DB_PROJECT_ID},
  method:{metric:'PostgreSQL EXPLAIN ANALYZE server execution time, successful canonical anonymous paid single-ticket checkout',blocks:6,samplesPerCase:72,warmupPerBlock:3,orderPrice:'100.00 CZK',fixture:'Same organization/form/input across modes; each successful checkout is validated then rolled back; baseline removes only the producer call in the transaction-local function definition.',cache:'Warm; rotated block order; no benchmark-generated concurrent load; ordinary workstation background load was not controlled',limits:'Does not measure total database CPU utilization, commit/fsync latency, GoTrue refresh work, outbound network or lock contention. No production data or configuration was used.'},
  scenarios:outcomes,idleWorkerSqlPoll:{normal:idleNormal,backlog10000:idleBacklog,description:'One empty SQL claim per selected active subscription tick; retention uses the existing cron job. Excludes upstream Auth refresh.'}};
}finally{for(const fn of cleanup.reverse())await fn();}
const file=process.argv[2];assert(file,'Output receipt path is required');await writeFile(file,JSON.stringify(receipt,null,2)+'\n');
process.stdout.write(JSON.stringify({receipt:file,scenarios:receipt.scenarios.map(({id,medianMs,deltaMedianMs,deltaMedianPct})=>({id,medianMs,deltaMedianMs,deltaMedianPct})),idlePollMedianMs:receipt.idleWorkerSqlPoll.normal.medianMs})+'\n');
