// Run sequentially after the SQL lane: its runner replaces functions and resets sequences.
// Provider acceptance below is a test double; projection and domain RPCs are real.
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {setTimeout as delay} from 'node:timers/promises';
import {assertLocalDatabaseUrl,assertDisposableDatabase} from '../../../web_client/tests/database/disposable_database.js';

const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const connectionString=process.env.DATABASE_URL;
assertLocalDatabaseUrl(connectionString);
const assertions=await readFile(new URL('../helpers/assertions.sql',import.meta.url),'utf8');
const fixtureSQL=await readFile(new URL('../helpers/payment_lifecycle_fixture.sql',import.meta.url),'utf8');
const fixtureClients=new WeakSet();

async function connect(){
 const c=new Client({connectionString});await c.connect();
 try{
  await assertDisposableDatabase(c);
  await c.query("SET statement_timeout='12s'; SET lock_timeout='8s'; SELECT set_config('festapp.email_wake','scheduled',false)");
  return c;
 }catch(error){await c.end();throw error;}
}
async function fixture(c,deposit=null){
 await c.query('BEGIN');
 if(!fixtureClients.has(c)){await c.query(assertions);await c.query(fixtureSQL);}
 const x=(await c.query('SELECT pg_temp.payment_attach_spot(pg_temp.payment_fixture($1)) x',[deposit])).rows[0].x;
 await c.query('COMMIT');fixtureClients.add(c);return x;
}
async function begin(c,x,role='authenticated'){
 await c.query('BEGIN');
 await c.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role',$2,true)",[x.actor,role]);
}
async function edit(c,x,price,command,expectBump=true){
 const version=BigInt((await c.query('SELECT email_payment_version FROM eshop.orders WHERE id=$1',[x.order])).rows[0].email_payment_version);
 await c.query('SET LOCAL ROLE authenticated');
 try{
  const r=(await c.query('SELECT public.update_ticket_products_client_sync_v1($1,$2,$3) r',[
   x.ticket,JSON.stringify([{id:x.product,price}]),command])).rows[0].r;
  assert.equal(r.status,'applied',JSON.stringify(r));
  await c.query('RESET ROLE');
  if(expectBump!==null)assert.equal(BigInt((await c.query('SELECT email_payment_version FROM eshop.orders WHERE id=$1',[x.order])).rows[0].email_payment_version),
   version+(expectBump?1n:0n),'one invalidation per product edit; none per replay');
  return r;
 }finally{await c.query('RESET ROLE').catch(()=>{});}
}
async function transaction(c,x,amount){
 return (await c.query("INSERT INTO eshop.transactions(date,amount,currency,bank_account_id,transaction_type) VALUES(now(),$1,'CZK',$2,'manual') RETURNING id",[amount,x.bank])).rows[0].id;
}
async function pair(c,tid,payment){
 return (await c.query("SELECT public.apply_transaction_pairing($1,$2,'test','system') r",[tid,payment])).rows[0].r;
}
async function cancel(c,x,command){
 await c.query('SET LOCAL ROLE authenticated');
 try{
  const r=(await c.query('SELECT public.storno_order_client_sync_v1($1,$2) r',[x.order,command])).rows[0].r;
  assert.equal(r.status,'applied',JSON.stringify(r));return r;
 }finally{await c.query('RESET ROLE').catch(()=>{});}
}
async function history(c,x){
 return (await c.query('SELECT coalesce(jsonb_agg(to_jsonb(h) ORDER BY id),\'[]\') h FROM eshop.orders_history h WHERE "order"=$1',[x.order])).rows[0].h;
}
async function identity(c,x){
 return (await c.query(`SELECT jsonb_build_object('ticket',t.id,'occasion',t.occasion,
  'products',(SELECT jsonb_agg(jsonb_build_object('id',opt.id,'order',opt."order",'ticket',opt.ticket,'product',opt.product) ORDER BY opt.id)
   FROM eshop.order_product_ticket opt WHERE opt."order"=$1),
  'spots',(SELECT coalesce(jsonb_agg(jsonb_build_object('id',s.id,'opt',s.order_product_ticket,'secret',s.secret) ORDER BY s.id),'[]')
   FROM eshop.spots s JOIN eshop.order_product_ticket opt ON opt.id=s.order_product_ticket WHERE opt."order"=$1)) identity
  FROM eshop.tickets t WHERE id=$2`,[x.order,x.ticket])).rows[0].identity;
}
async function evidence(c,x){
 const state=(await c.query(`SELECT o.state,o.data,o.price::text,p.paid::text,o.email_payment_version::text version,t.state ticket
  FROM eshop.orders o JOIN eshop.payment_info p ON p.id=o.payment_info JOIN eshop.tickets t ON t.id=$2 WHERE o.id=$1`,[x.order,x.ticket])).rows[0];
 const messages=(await c.query('SELECT message_id,message_kind,source_version::text,workflow_state,post_action_state FROM public.email_messages WHERE order_id=$1 ORDER BY id',[x.order])).rows;
 return {state,messages,history:await history(c,x)};
}
async function verify(c,x,before,{state='ordered',paid,price,historyAdded=1,historyState=state,retainIdentity=true}){
 const e=await evidence(c,x);
 assert.equal(e.state.state,state);assert.equal(e.state.ticket,state);
 assert.equal(Number(e.state.paid),paid);assert.equal(Number(e.state.price),price);
 const oldIds=new Set(before.history.map(h=>h.id));
 assert.deepEqual(e.history.filter(h=>oldIds.has(h.id)),before.history,'older snapshots remain byte-for-byte unchanged');
 assert.equal(e.history.length,before.history.length+historyAdded,'only the owning domain event adds history');
 const added=e.history.filter(h=>!oldIds.has(h.id));
 for(const h of added){
  assert.equal(h.state,historyState,'event snapshot records its actual reconciled state');
  assert.equal(Number(h.price),price);assert.deepEqual(h.data,e.state.data);
 }
 const active=e.messages.filter(m=>m.message_kind==='order_tickets' &&
  ['pending','preparing','sending','retry_wait','unknown','blocked'].includes(m.workflow_state));
 assert.ok(active.length<=1,'at most one current valid ticket intent set');
 assert.ok(active.every(m=>m.source_version===e.state.version),'every active ticket intent uses the final version');
 if(state==='ordered'||state==='storno')assert.equal(active.length,0,'ineligible admission has no current ticket intent');
 if(retainIdentity)assert.deepEqual(await identity(c,x),before.identity,'ticket/OPT/spot identities survive reconciliation');
 return e;
}
async function before(c,x){return {...await evidence(c,x),identity:await identity(c,x)};}
async function pid(c){return (await c.query('SELECT pg_backend_pid() pid')).rows[0].pid;}
// Attach rejection handlers immediately: a deadlock is a failure, never an unhandled promise.
function pending(operation){return operation.then(value=>({value}),error=>({error}));}
async function result(operation){const outcome=await operation;if(outcome.error)throw outcome.error;return outcome.value;}
async function blocked(observer,waiting,holder){
 const deadline=Date.now()+5000;
 while(Date.now()<deadline){
  const blockers=(await observer.query('SELECT pg_blocking_pids($1) blockers',[waiting])).rows[0].blockers;
  if(blockers.includes(holder))return;
  await delay(10);
 }
 throw new Error(`Expected PostgreSQL backend ${waiting} to block on ${holder}`);
}
async function close(...clients){
 await Promise.allSettled(clients.map(async c=>{await c.query('ROLLBACK');await c.end();}));
}
async function replayEdit(c,x,price,command,original){
 const snapshot=await evidence(c,x);await begin(c,x);
 assert.deepEqual(await edit(c,x,price,command,false),original,'same command UUID replays the committed response');
 await c.query('COMMIT');
 assert.deepEqual(await evidence(c,x),snapshot,'receipt replay adds no effects');
 const count=(await c.query('SELECT count(*)::int n FROM public.client_mutation_receipts WHERE command_id=$1 AND status=\'completed\'',[command])).rows[0].n;
 assert.equal(count,1);
}

for(const action of ['pair','unpair']){
 for(const first of ['bank','edit']){
  test(`${action} versus product edit: ${first} owns the real lock first`,async()=>{
   const setup=await connect(),bank=await connect(),editor=await connect();
   try{
    const x=await fixture(setup),command=randomUUID();
    const tid=await transaction(setup,x,1000);
    if(action==='unpair'){
     await begin(setup,x);assert.equal((await pair(setup,tid,x.payment)).status,'paired');await setup.query('COMMIT');
    }
    const prior=await before(setup,x),price=action==='pair'?1100:900;
    await begin(bank,x);await begin(editor,x);
    const bankPid=await pid(bank),editPid=await pid(editor);
    let edited;
    if(first==='bank'){
     assert.equal((await pair(bank,tid,action==='pair'?x.payment:null)).status,action==='pair'?'paired':'unpaired');
     const editing=pending(edit(editor,x,price,command,null));
     await blocked(setup,editPid,bankPid);
     await bank.query('COMMIT');edited=await result(editing);await editor.query('COMMIT');
    }else{
     // This is the editor's actual first acquisition boundary. Starting pairing
     // behind it exposes payment->form/order inversions before editor money writes.
     await editor.query('SELECT public.lock_order_capacity_scope_internal(ARRAY[$1::bigint])',[x.order]);
     const pairing=pending(pair(bank,tid,action==='pair'?x.payment:null));
     await blocked(setup,bankPid,editPid);
     edited=await edit(editor,x,price,command);
     await editor.query('COMMIT');
     assert.equal((await result(pairing)).status,action==='pair'?'paired':'unpaired');await bank.query('COMMIT');
    }
    const final=await verify(setup,x,prior,{paid:action==='pair'?1000:0,price,historyState:action==='unpair'&&first==='edit'?'paid':'ordered'});
    assert.equal(BigInt(final.state.version),BigInt(prior.state.version)+(first==='bank'||action==='unpair'?2n:1n),
     'exactly one invalidation per effective edit/payment eligibility transition');
    await replayEdit(editor,x,price,command,edited);
    const snapshot=await evidence(setup,x);await begin(bank,x);
    assert.equal((await pair(bank,tid,action==='pair'?x.payment:null)).status,'unchanged');await bank.query('COMMIT');
    assert.deepEqual(await evidence(setup,x),snapshot,'repeated bank fact adds no transition effects');
   }finally{await close(editor,bank,setup);}
  });
 }
}

test('cancellation blocks bank recalculation and never restores cancelled admission',async()=>{
 const setup=await connect(),cancelling=await connect(),bank=await connect();
 try{
  const x=await fixture(setup),command=randomUUID(),tid=await transaction(setup,x,1000);
  const prior=await before(setup,x);
  await begin(cancelling,x);const cancelled=await cancel(cancelling,x,command);
  await begin(bank,x);const bankPid=await pid(bank),cancelPid=await pid(cancelling);
  const pairing=pending(pair(bank,tid,x.payment));
  await blocked(setup,bankPid,cancelPid);await cancelling.query('COMMIT');
  assert.equal((await result(pairing)).status,'paired');await bank.query('COMMIT');
  await verify(setup,x,prior,{state:'storno',paid:1000,price:0,retainIdentity:false});
  const snapshot=await evidence(setup,x);await begin(cancelling,x);
  // Replay retains its original response despite the now cancelled resource.
  await cancelling.query('SET LOCAL ROLE authenticated');
  assert.deepEqual((await cancelling.query('SELECT public.storno_order_client_sync_v1($1,$2) r',[x.order,command])).rows[0].r,cancelled);
  await cancelling.query('COMMIT');assert.deepEqual(await evidence(setup,x),snapshot);
 }finally{await close(bank,cancelling,setup);}
});

test('late accepted old-version email waits for edit and cannot restore unpaid admission',async()=>{
 const setup=await connect(),editor=await connect(),accepting=await connect();
 try{
  const x=await fixture(setup),command=randomUUID(),tid=await transaction(setup,x,1000);
  await begin(setup,x);await pair(setup,tid,x.payment);await setup.query('COMMIT');
  const message=(await setup.query(`SELECT message_id,source_version FROM public.email_messages WHERE order_id=$1
   AND message_kind='order_tickets' AND source_version=(SELECT email_payment_version FROM eshop.orders WHERE id=$1)`,[x.order])).rows[0];
  assert.ok(message,'paid transition enqueues the actual ticket intent');
  // Simulate provider acceptance, then race its real SQL post-action projection.
  await setup.query(`UPDATE public.email_messages SET workflow_state='accepted',accepted_at=now(),
   post_action=jsonb_build_object('ticket_ids',jsonb_build_array($2::bigint)) WHERE message_id=$1`,[message.message_id,x.ticket]);
  const prior=await before(setup,x);
  await begin(editor,x);await editor.query('SELECT public.lock_order_capacity_scope_internal(ARRAY[$1::bigint])',[x.order]);
  await begin(accepting,x,'service_role');
  const acceptingPid=await pid(accepting),editorPid=await pid(editor);
  const acceptance=pending(accepting.query('SELECT public.apply_email_post_actions($1)',[message.message_id]));
  await blocked(setup,acceptingPid,editorPid);
  const edited=await edit(editor,x,1100,command);await editor.query('COMMIT');
  await result(acceptance);await accepting.query('COMMIT');
  const e=await verify(setup,x,prior,{paid:1000,price:1100});
  assert.notEqual(e.state.version,String(message.source_version),'edit invalidates the accepted message source');
  assert.equal(e.messages.find(m=>m.message_id===message.message_id).post_action_state,'done');
  assert.equal(e.history.filter(h=>h.state==='sent').length,0,'stale acceptance adds no false sent snapshot');
  await replayEdit(editor,x,1100,command,edited);
 }finally{await close(accepting,editor,setup);}
});

test('moving pairing locks stored old/new form scopes in order before either payment write',async()=>{
 const setup=await connect(),editor=await connect(),bank=await connect();
 try{
  // Create the receiving form first: sorted acquisition must lock it before
  // waiting on the later, original form, independently of movement direction.
  const target=await fixture(setup),source=await fixture(setup),command=randomUUID();
  assert.ok(BigInt(target.form)<BigInt(source.form));
  assert.notEqual(source.payment,target.payment);
  const tid=await transaction(setup,source,1000);
  await begin(setup,source);await pair(setup,tid,source.payment);await setup.query('COMMIT');
  const sourceBefore=await before(setup,source),targetBefore=await before(setup,target);
  assert.equal(sourceBefore.state.state,'paid');assert.equal(targetBefore.state.state,'ordered');
  await begin(editor,source);
  await editor.query('SELECT public.lock_order_capacity_scope_internal(ARRAY[$1::bigint])',[source.order]);
  await begin(bank,source);const bankPid=await pid(bank),editorPid=await pid(editor);
  const movement=pending(pair(bank,tid,target.payment));
  await blocked(setup,bankPid,editorPid);
  // Observe the other scope as a real row lock, not an assumed caller list.
  await setup.query('BEGIN');
  try{
   await assert.rejects(setup.query('SELECT id FROM public.forms WHERE id=$1 FOR UPDATE NOWAIT',[target.form]),
    error=>error.code==='55P03','movement holds the lower target form while waiting for the original form');
  }finally{await setup.query('ROLLBACK');}
  const edited=await edit(editor,source,1100,command);await editor.query('COMMIT');
  assert.equal((await result(movement)).status,'paired');await bank.query('COMMIT');
  const sourceFinal=await verify(setup,source,sourceBefore,{paid:0,price:1100});
  const targetFinal=await verify(setup,target,targetBefore,{state:'paid',paid:1000,price:1000,historyAdded:0});
  assert.equal(BigInt(sourceFinal.state.version),BigInt(sourceBefore.state.version)+1n,
   'product edit invalidates once; moving already-ineligible funds adds no invalidation');
  assert.equal(BigInt(targetFinal.state.version),BigInt(targetBefore.state.version)+1n,
   'receiving eligibility transition invalidates exactly once');
  assert.equal(targetFinal.messages.filter(m=>m.message_kind==='order_tickets'&&
   m.source_version===targetFinal.state.version&&m.workflow_state==='pending').length,1,
   'receiving order owns exactly one current ticket intent');
  assert.equal(String((await setup.query('SELECT payment_info FROM eshop.transactions WHERE id=$1',[tid])).rows[0].payment_info),String(target.payment));
  const movements=(await setup.query(`SELECT old_payment_info_id,new_payment_info_id FROM eshop.transaction_pairing_events
   WHERE transaction_id=$1 ORDER BY id`,[tid])).rows;
  assert.equal(movements.length,2,'initial pairing and one actual move, without duplicate events');
  assert.equal(String(movements[1].old_payment_info_id),String(source.payment));
  assert.equal(String(movements[1].new_payment_info_id),String(target.payment));
  await replayEdit(editor,source,1100,command,edited);
  assert.deepEqual(await evidence(setup,target),targetFinal,'source receipt replay cannot affect receiving order');
  await begin(bank,source);assert.equal((await pair(bank,tid,target.payment)).status,'unchanged');await bank.query('COMMIT');
  assert.deepEqual(await evidence(setup,source),sourceFinal);
  assert.deepEqual(await evidence(setup,target),targetFinal);
 }finally{await close(bank,editor,setup);}
});
