import test from 'node:test';
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
assertLocalDatabaseUrl(process.env.DATABASE_URL);
const clients=[new Client({connectionString:process.env.DATABASE_URL}),new Client({connectionString:process.env.DATABASE_URL})];
for(const c of clients){await c.connect();await assertDisposableDatabase(c);await c.query("SET request.jwt.claim.role='service_role'; SET lock_timeout='5s'");}
const [a,b]=clients;
const scalar=async(c,sql,values=[]) => (await c.query(sql,values)).rows[0].v;
const rpc=(c,name,params=[])=>scalar(c,`SELECT public.${name}(${params.map((_,i)=>'$'+(i+1)).join(',')}) v`,params);
let org,occ,ids=[];
try{
 org=await scalar(a,"INSERT INTO public.organizations(title) VALUES('Queue concurrency') RETURNING id v");
 occ=await scalar(a,"INSERT INTO public.occasions(title,link,organization,start_time,end_time) VALUES('Queue concurrency',gen_random_uuid()::text,$1,now(),now()+interval '1 day') RETURNING id v",[org]);
 await a.query("INSERT INTO eshop.ticket_wallet_integrations(organization,issuer,environment,web_origin) VALUES($1,'1234','concurrency','https://queue.invalid')",[org]);
 for(let n=0;n<3;n++){
  const tid=await scalar(a,"INSERT INTO eshop.tickets(occasion,state) VALUES($1,'paid') RETURNING id v",[occ]);ids.push(tid);
  await a.query("INSERT INTO eshop.ticket_wallet_objects(ticket_id,organization,occasion,issuer,environment,object_id,class_id) VALUES($1,$2,$3,'1234','concurrency','1234.concurrent-'||$1::bigint::text,'1234.concurrent-class-'||$3::bigint::text)",[tid,org,occ]);
 }
 await rpc(a,'enqueue_wallet_class_internal',[ids[0]]);
 await rpc(a,'enqueue_ticket_wallet_internal',[ids]);
 await test('two real sessions share one class lease and object dependency',async()=>{
  const cls=await rpc(a,'claim_ticket_wallet',[ids[0]]);assert.equal(cls.kind,'class');
  assert.equal(await rpc(b,'claim_ticket_wallet',[ids[1]]),null);
  assert.equal(await rpc(a,'finish_ticket_wallet',[ids[0],cls.lease,true]),true);
 });
 await test('enqueue during claimed network work survives captured acknowledgement',async()=>{
  const old=await rpc(a,'claim_ticket_wallet',[ids[0]]);
  await rpc(b,'enqueue_ticket_wallet_internal',[[ids[0]]]);
  assert.equal(await rpc(a,'finish_ticket_wallet',[ids[0],old.lease,true]),true);
  const next=await rpc(b,'claim_ticket_wallet',[ids[0]]);assert(next.version>old.version);
  assert.equal(await rpc(a,'finish_ticket_wallet',[ids[0],old.lease,true]),false);
  await rpc(b,'finish_ticket_wallet',[ids[0],next.lease,true]);
 });
 await test('SKIP LOCKED claims another object without waiting for a held work row',async()=>{
  await a.query('BEGIN');const first=await rpc(a,'claim_ticket_wallet',[ids[1]]);
  const second=await rpc(b,'claim_ticket_wallet',[ids[2]]);assert(first&&second);assert.notEqual(first.lease,second.lease);
  await a.query('COMMIT');
  await rpc(a,'finish_ticket_wallet',[ids[1],first.lease,true]);await rpc(b,'finish_ticket_wallet',[ids[2],second.lease,true]);
 });
 await test('scope changes during a fanout batch restart its durable cursor',async()=>{
  await rpc(a,'enqueue_wallet_scope_internal',[occ]);
  await a.query('BEGIN');await rpc(a,'maintain_ticket_wallet',[1]);
  const changed=rpc(b,'enqueue_wallet_scope_internal',[occ]);
  await a.query('COMMIT');await changed;
  await rpc(a,'maintain_ticket_wallet',[1]);
  const scope=(await a.query("SELECT requested,cursor_version,cursor_ticket FROM eshop.ticket_wallet_work WHERE kind='occasion' AND resource=$1",[occ])).rows[0];
  assert.equal(scope.requested,scope.cursor_version);assert.equal(scope.cursor_ticket,ids[0]);
 });
 await test('pause waits for short claim transactions, blocks new claims, and permits in-flight ack',async()=>{
  await a.query('BEGIN');const claimed=await rpc(a,'claim_ticket_wallet',[ids[0]]);assert(claimed);
  let paused=false;const pause=rpc(b,'pause_ticket_wallet',[org,true]).then(()=>{paused=true;});
  await new Promise(resolve=>setTimeout(resolve,30));assert.equal(paused,false);
  await a.query('COMMIT');await pause;
  assert.equal(await rpc(a,'claim_ticket_wallet',[ids[1]]),null);
  assert.equal(await rpc(a,'finish_ticket_wallet',[claimed.ticketId,claimed.lease,true]),true);
  await rpc(a,'enqueue_ticket_wallet_internal',[[ids[1]]]);
  await rpc(b,'pause_ticket_wallet',[org,false]);
  assert(await rpc(a,'claim_ticket_wallet',[ids[1]]));
 });
}finally{
 await a.query('ROLLBACK');
 if(org){await a.query('DELETE FROM eshop.ticket_wallet_work WHERE organization=$1',[org]);await a.query('DELETE FROM eshop.ticket_wallet_objects WHERE organization=$1',[org]);await a.query('DELETE FROM eshop.ticket_wallet_integrations WHERE organization=$1',[org]);await a.query('DELETE FROM eshop.tickets WHERE occasion=$1',[occ]);await a.query('DELETE FROM public.occasions WHERE id=$1',[occ]);await a.query('DELETE FROM public.organizations WHERE id=$1',[org]);}
 for(const c of clients)await c.end();
}
