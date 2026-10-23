import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {paidAtomicSwap,executor} from './seat-fixtures.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function preview(s,spots=[s.first]){const f=s.f;return(await s.db.query('select preview_blueprint_ticket_cancellation($1,$2,$3,$4,$5) v',[f.occasion,f.org,f.unit,f.blueprint,spots])).rows[0].v;}
async function apply(s,p,command=randomUUID()){const f=s.f;return(await s.db.query('select cancel_blueprint_tickets($1,$2,$3,$4,$5,$6,$7,$8) v',[f.occasion,f.org,f.unit,f.blueprint,p.requestedSpotIds,p.ticketIds,p.confirmationHash,command])).rows[0].v;}
async function state(s){await s.db.query('RESET ROLE');const r=(await s.db.query(`select jsonb_build_object('orders',(select jsonb_agg(to_jsonb(o) order by id) from eshop.orders o where occasion=$1),'tickets',(select jsonb_agg(to_jsonb(t) order by id) from eshop.tickets t where occasion=$1),'spots',(select jsonb_agg(to_jsonb(t) order by id) from eshop.spots t where occasion=$1),'history',(select jsonb_agg(to_jsonb(t) order by id) from eshop.orders_history t where "order" in(select id from eshop.orders where occasion=$1)),'emails',(select jsonb_agg(to_jsonb(t) order by id) from email_messages t where occasion=$1)) v`,[s.f.occasion])).rows[0].v;await s.db.query('SET LOCAL ROLE authenticated');return r;}
test('cancellation expands atomic seats; real quote rolls back; commit and exact replay use one receipt',options,async t=>{
 const s=await paidAtomicSwap(t),before=await state(s),p=await preview(s);assert.equal(p.ticketIds.length,2);assert.deepEqual(p.affectedSpotIds,s.source.map(b=>b.spotId).sort((a,b)=>a-b));assert.equal(p.orders[0].beforeAmount,'200.00');assert.equal(p.orders[0].afterState,'storno');assert.deepEqual(await state(s),before);
 const command=randomUUID(),done=await apply(s,p,command);assert.equal(done.status,'applied',JSON.stringify(done));const after=await state(s);assert(after.tickets.filter(t=>p.ticketIds.includes(Number(t.id))).every(t=>t.state==='storno'));assert(after.spots.filter(t=>p.affectedSpotIds.includes(Number(t.id))).every(t=>t.order_product_ticket===null));assert.deepEqual(await apply(s,p,command),done);assert.deepEqual(await state(s),after);
});
test('changed money invalidates the complete cancellation without releasing a seat',options,async t=>{
 const s=await paidAtomicSwap(t),p=await preview(s);await s.db.query('RESET ROLE');await s.db.query('update eshop.payment_info set paid=paid+1 where id=$1',[s.payment]);await s.db.query('SET LOCAL ROLE authenticated');const before=await state(s),done=await apply(s,p);assert.equal(done.status,'rejected');assert.deepEqual(await state(s),before);
});
test('free member rejects whole selection; role revocation denies receipt replay',options,async t=>{
 const s=await paidAtomicSwap(t),before=await state(s);await s.db.query('SAVEPOINT bad_selection');await assert.rejects(preview(s,[s.first,s.second]),e=>e.code==='23514');await s.db.query('ROLLBACK TO SAVEPOINT bad_selection');assert.deepEqual(await state(s),before);
 const p=await preview(s),command=randomUUID();await apply(s,p,command);await s.db.query('RESET ROLE');await s.db.query('delete from occasion_users where occasion=$1 and "user"=$2',[s.f.occasion,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');await assert.rejects(apply(s,p,command),e=>e.code==='42501');
});
test('MCP real scoped cancellation retries same UUID after lost acknowledgement',options,async t=>{
 const s=await paidAtomicSwap(t),ex=executor(s.db,s.f),args={occasionId:s.f.occasion,blueprintId:s.f.blueprint,spotIds:[s.first]};
 const p=await ex.ops.invoke('seats.preview_cancel',args);assert.equal(p.ok,true,JSON.stringify(p));const q=p.data;
 const commandId=randomUUID(),write={...args,ticketIds:q.ticketIds,confirmationHash:q.confirmationHash,commandId};ex.stats.lose=true;const lost=await ex.ops.invoke('seats.cancel_tickets',write);assert.equal(lost.ok,false);const done=await ex.ops.invoke('seats.cancel_tickets',write);assert.equal(done.ok,true,JSON.stringify(done));assert.equal(done.data.commandId,commandId);assert.equal(ex.stats.calls,3);console.log('cancellation serialized domain bytes',JSON.stringify(ex.stats.payloadBytes));
});

test('partial cancellation retains unselected tickets and paid money; other-map seats of selected tickets are disclosed',options,async t=>{
 const s=await paidAtomicSwap(t);await s.db.query('RESET ROLE');
 const extra=Number((await s.db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[s.f.occasion])).rows[0].id);
 await s.db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3)',[s.order,extra,s.fx.product]);
 await s.db.query("update eshop.orders set price=300,data=jsonb_set(data,'{tickets}',data->'tickets'||jsonb_build_array(jsonb_build_object('id',$2::bigint,'products',jsonb_build_array(_swap_spots_generate_product_json($3,NULL))))) where id=$1",[s.order,extra,s.fx.product]);await s.db.query('update eshop.payment_info set amount=300,paid=300 where id=$1',[s.payment]);
 const other=Number((await s.db.query("insert into eshop.blueprints(occasion,title) values($1,'Other map') returning id",[s.f.occasion])).rows[0].id);
 const item=(await s.db.query('select order_product_ticket from eshop.spots where id=$1',[s.first])).rows[0].order_product_ticket;
 const spot=Number((await s.db.query("insert into eshop.spots(occasion,blueprint,title,order_product_ticket,product) values($1,$2,'Other ticket seat',$3,$4) returning id",[s.f.occasion,other,item,s.fx.product])).rows[0].id);
 await s.db.query('SET LOCAL ROLE authenticated');const p=await preview(s);assert(p.affectedSpotIds.includes(spot));assert(p.seats.some(e=>e.blueprintId===other));assert.equal(p.orders[0].afterAmount,'100.00');const done=await apply(s,p);assert.equal(done.status,'applied');
 await s.db.query('RESET ROLE');assert.equal((await s.db.query('select state from eshop.tickets where id=$1',[extra])).rows[0].state,'paid');assert.equal(Number((await s.db.query('select paid from eshop.payment_info where id=$1',[s.payment])).rows[0].paid),300);
});

test('printed batch cancellation follows canonical void policy without changing printed contents',options,async t=>{
 const s=await paidAtomicSwap(t),p=await preview(s);await s.db.query('RESET ROLE');
 const stock=Number((await s.db.query('select allocate_ticket_order_identity_internal($1) id',[s.fx.form])).rows[0].id);await s.db.query("update eshop.orders set state='stock',price=null,payment_info=null where id=$1",[stock]);
 const batch=(await s.db.query("insert into eshop.ticket_batches(occasion,form,stock_order_id,title,created_by,currency_code,snapshot) values($1,$2,$3,'Synthetic cancellation guard',$4,'CZK','{}') returning id",[s.f.occasion,s.fx.form,stock,s.f.actor])).rows[0].id;
 await s.db.query('insert into eshop.ticket_batch_items(batch_id,ticket_id,ordinal,sale_order_id) values($1,$2,1,$3)',[batch,p.ticketIds[0],s.order]);await s.db.query('SET LOCAL ROLE authenticated');const fresh=await preview(s),done=await apply(s,fresh);assert.equal(done.status,'applied');
 await s.db.query('RESET ROLE');assert.equal((await s.db.query('select count(*)::int n from eshop.ticket_batch_items where batch_id=$1',[batch])).rows[0].n,1);assert.equal((await s.db.query('select state from eshop.tickets where id=$1',[p.ticketIds[0]])).rows[0].state,'storno');
});

test('concurrent cancellations serialize; stale second approval changes nothing and original receipt replays',options,async t=>{
 const s=await paidAtomicSwap(t,true),p=await preview(s),one=randomUUID(),two=randomUUID();await s.db.query('COMMIT');
 const {openDisposableDatabase}=await import('./postgres.mjs');const other=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let pending;
 try{
  await s.db.query('BEGIN');await s.db.query("select set_config('request.jwt.claim.sub',$1,true)",[s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');const committed=await apply(s,p,one);assert.equal(committed.status,'applied');
  await other.query('BEGIN');await other.query("set local statement_timeout='5s'");await other.query("select set_config('request.jwt.claim.sub',$1,true)",[s.f.actor]);await other.query('SET LOCAL ROLE authenticated');
  pending=apply({...s,db:other},p,two);let blocked=false;
  await s.db.query('RESET ROLE');for(let i=0;i<100;i++){if((await s.db.query('select $1::int=any(pg_blocking_pids($2)) blocked',[s.db.processID,other.processID])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'actual cancellation waits on canonical scope lock');await s.db.query('COMMIT');
  assert.equal((await pending).status,'rejected');pending=null;await other.query('COMMIT');
  await s.db.query('BEGIN');await s.db.query("select set_config('request.jwt.claim.sub',$1,true)",[s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');const after=await state(s);assert.deepEqual(await apply(s,p,one),committed);assert.deepEqual(await state(s),after);
 }finally{await s.db.query('ROLLBACK');await other.query('ROLLBACK');if(pending)await pending.catch(()=>{});await other.end();}
});
