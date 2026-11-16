/** Actual local PostgreSQL fanout, entirely rolled back. No provider dispatch. */
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../web_client/package.json',import.meta.url));const {Client}=require('pg');
assertLocalDatabaseUrl(process.env.DATABASE_URL);const db=new Client({connectionString:process.env.DATABASE_URL});await db.connect();await assertDisposableDatabase(db);
const one=async(sql,p=[]) => (await db.query(sql,p)).rows[0];const report=[];
try{
 for(const count of [1000,10000]){
  await db.query('BEGIN');await db.query("SET LOCAL request.jwt.claim.role='service_role'");
  const {id:org}=await one("INSERT INTO public.organizations(title) VALUES('Local queue capacity') RETURNING id");
  const {id:occ}=await one("INSERT INTO public.occasions(title,link,organization,start_time,end_time) VALUES('Local queue capacity',gen_random_uuid()::text,$1,now(),now()+interval '1 day') RETURNING id",[org]);
  await db.query("INSERT INTO eshop.ticket_wallet_integrations(organization,issuer,environment,web_origin) VALUES($1,'1234','capacity','https://queue.invalid')",[org]);
  await db.query("INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id) SELECT 70000000+n,$1,$2,'1234','capacity','1234.capacity-'||n,'1234.capacity-class' FROM generate_series(1,$3::int) n",[org,occ,count]);
  await db.query('SELECT public.enqueue_wallet_class_internal(70000001)');
  await db.query('SELECT public.enqueue_ticket_wallet_internal(ARRAY(SELECT ticket_id FROM eshop.ticket_wallet_objects WHERE organization=$1))',[org]);
  const started=performance.now();await db.query('SELECT public.enqueue_wallet_scope_internal($1)',[occ]);const batches=[];
  for(let i=0;i<=Math.ceil(count/100);i++){
   const t=performance.now();await db.query('SELECT public.maintain_ticket_wallet(100)');batches.push(performance.now()-t);
   const {done}=await one("SELECT applied=requested done FROM eshop.ticket_wallet_work WHERE kind='occasion' AND resource=$1",[String(occ)]);if(done)break;
  }
  const scopeMs=performance.now()-started;const sorted=[...batches].sort((a,b)=>a-b);
  const burstStart=performance.now();await db.query('SELECT public.enqueue_ticket_wallet_internal(ARRAY(SELECT ticket_id FROM eshop.ticket_wallet_objects WHERE organization=$1))',[org]);
  const {rows,minimum_requested}=await one("SELECT count(*)::int rows,min(requested)::int minimum_requested FROM eshop.ticket_wallet_work WHERE kind='object' AND organization=$1",[org]);
  if(rows!==count||minimum_requested!==3)throw new Error('incomplete scope/burst propagation');
  report.push({registrations:count,scopeFanoutMs:Math.round(scopeMs),batchSize:100,batches:batches.length,batchP95Ms:Math.round(sorted[Math.ceil(sorted.length*.95)-1]),batchMaxMs:Math.round(sorted.at(-1)),invalidationEnqueueMs:Math.round(performance.now()-burstStart),providerCalls:0,rows,minimumRequested:minimum_requested});
  await db.query('ROLLBACK');
 }
 console.log(JSON.stringify(report,null,2));
}finally{await db.query('ROLLBACK');await db.end();}
