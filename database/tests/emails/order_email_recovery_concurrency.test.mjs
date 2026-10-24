import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {createRequire} from 'node:module';
const require=createRequire(new URL('../../../web_client/package.json',import.meta.url));
const {Client}=require('pg');
const url=process.env.DATABASE_URL;
if (!url || new URL(url).hostname!=='127.0.0.1' || new URL(url).port!=='55432') throw Error('Disposable localhost DB required');
async function connect(){ const c=new Client({connectionString:url});await c.connect();await c.query("SET statement_timeout='10s'");return c; }
async function fixture(c,state='ordered'){
 assert.equal((await c.query("SELECT project FROM festapp_test_support.disposable_environment")).rows[0]?.project,'festapp-db-tests-pg15');
 assert.ok((await c.query('SELECT worker_url FROM public.email_capacity')).rows.every(r=>r.worker_url===null),'no live worker');
 const actor=randomUUID(), email=randomUUID()+'@example.invalid';
 await c.query('INSERT INTO auth.users(id) VALUES($1)',[actor]);
 const {rows:[f]}=await c.query(`WITH org AS(INSERT INTO public.organizations(title) VALUES('Email recovery concurrency') RETURNING id),
 un AS(INSERT INTO public.units(title,organization) SELECT 'Synthetic',id FROM org RETURNING id,organization),
 oc AS(INSERT INTO public.occasions(title,organization,unit,link,start_time,end_time) SELECT 'Synthetic',organization,id,$1,now(),now()+interval '1 day' FROM un RETURNING id,organization,unit) SELECT * FROM oc`,[randomUUID()]);
 await c.query('INSERT INTO public.user_info(id,organization) VALUES($1,$2)',[actor,f.organization]);
 await c.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order,is_editor_order_view) VALUES($1,$2,true,true)',[f.id,actor]);
 const {rows:[o]}=await c.query(`INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code)
 VALUES(public.next_order_sequence($1),public.generate_order_symbol(),$1,$2,jsonb_build_object('email',$3::text),100,'CZK') RETURNING *`,[f.id,state,email]);
 const code=state==='ordered'?'TICKET_ORDER_CONFIRMATION':'ORDER_TICKETS';
 const {rows:[m]}=await c.query('SELECT public.enqueue_order_email($1,$2,$3,$4,$5) result',[code,{order_id:o.id},f.organization,f.id,f.unit]);
 const source=m.result.message_id;
 await c.query("UPDATE public.email_messages SET workflow_state='dead',bounced_at=now() WHERE message_id=$1",[source]);
 const {rows:[facts]}=await c.query('SELECT public.order_email_payment_fingerprint($1) token',[o.id]);
 return {...f,order:o,actor,source,email,fingerprint:facts.token};
}
async function repair(c,f,command=randomUUID(),email=f.email){
 await c.query('BEGIN');
 try {
  await c.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true),set_config('festapp.email_wake','scheduled',true)",[f.actor]);
  await c.query('SET LOCAL ROLE authenticated');
  const {rows:[r]}=await c.query('SELECT public.repair_order_email_client_sync_v1($1,$2,$3,$4,$5,$6,true,$7,$8) result',
   [f.order.id,f.email,f.order.state,f.order.email_payment_version,email,f.source,command,f.fingerprint]);
  await c.query('COMMIT');return r.result;
 } catch(e){await c.query('ROLLBACK');throw e;}
}
for(const state of ['ordered','paid']) test(`two commands serialize one active ${state} resend and replay after commit`,async()=>{
 const setup=await connect(),a=await connect(),b=await connect();
 try {
  const f=await fixture(setup,state),commands=[randomUUID(),randomUUID()];
  const result=await Promise.all([repair(a,f,commands[0]),repair(b,f,commands[1])]);
  assert.deepEqual(result.map(r=>r.code).sort(),[200,409]);
  const winner=result.findIndex(r=>r.code===200);
  assert.deepEqual(await repair(a,f,commands[winner]),result[winner]);
  const {rows:[count]}=await setup.query("SELECT count(*)::int n FROM public.email_messages WHERE order_id=$1 AND workflow_state IN ('pending','preparing','sending','unknown','retry_wait')",[f.order.id]);
  assert.equal(count.n,1);
 } finally {await Promise.all([setup.end(),a.end(),b.end()]);}
});
for(const transition of ['payment','cancel']) test(`order lock fences stale repair racing ${transition}`,async()=>{
 const setup=await connect(),writer=await connect(),command=await connect();
 try {
  const f=await fixture(setup);
  await writer.query('BEGIN');
  await writer.query(`UPDATE eshop.orders SET state=$2,email_payment_version=email_payment_version+1 WHERE id=$1`,[f.order.id,transition==='payment'?'paid':'storno']);
  const pending=repair(command,f);
  await writer.query('COMMIT');
  assert.equal((await pending).code,409);
  assert.equal((await setup.query('SELECT count(*)::int n FROM public.email_messages WHERE order_id=$1',[f.order.id])).rows[0].n,1);
 } finally {await writer.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),command.end()]);}
});

test('form-first locking serializes field removal without recreating a deleted response',async()=>{
 const setup=await connect(),writer=await connect(),command=await connect();
 try {
  const f=await fixture(setup);
  const {rows:[form]}=await setup.query("INSERT INTO public.forms(occasion,title) VALUES($1,'Recovery contact') RETURNING id",[f.id]);
  const {rows:[field]}=await setup.query("INSERT INTO public.form_fields(form,type) VALUES($1,'email') RETURNING id",[form.id]);
  await setup.query('UPDATE eshop.orders SET form=$2 WHERE id=$1',[f.order.id,form.id]);
  await writer.query('BEGIN');
  await writer.query('SELECT id FROM public.forms WHERE id=$1 FOR UPDATE',[form.id]);
  await writer.query('DELETE FROM public.form_fields WHERE id=$1',[field.id]);
  const pending=repair(command,f);
  await writer.query('COMMIT');
  assert.equal((await pending).code,200);
  const {rows:[o]}=await setup.query('SELECT data FROM eshop.orders WHERE id=$1',[f.order.id]);
  assert.equal((o.data.fields??[]).some(e=>Object.hasOwn(e,field.id)),false);
 } finally {await writer.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),command.end()]);}
});

test('issued begin_email_send permit prevents racing resend, and contact-only save preserves its recipient',async()=>{
 const setup=await connect(),gateway=await connect(),command=await connect();
 try {
  const f=await fixture(setup);
  await setup.query("SELECT set_config('request.jwt.claim.role','service_role',false)");
  await setup.query("UPDATE public.email_messages SET workflow_state='cancelled' WHERE workflow_state IN ('pending','preparing','sending','retry_wait','unknown','blocked')");
  await setup.query("UPDATE public.email_messages SET workflow_state='pending',bounced_at=NULL WHERE message_id=$1",[f.source]);
  await setup.query("UPDATE public.email_capacity SET paused=false,shared_account=false,quota_at=now(),max_rate=100,daily_quota=10000,provider_sent_24h=0,next_send_at=now(),circuit_until=NULL,probe_until=NULL");
  const {rows:[claim]}=await setup.query('SELECT public.claim_email() result');
  const row=claim.result;assert.equal(row.message_id,f.source);
  await setup.query('SELECT public.prepare_email($1,$2,$3)',[row.message_id,row.lease_token,{sealed:'fence-fixture'}]);
  await gateway.query('BEGIN');
  await gateway.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
  const {rows:[permit]}=await gateway.query('SELECT public.begin_email_send($1,$2) result',[row.attempt_id,row.lease_token]);
  assert.equal(permit.result.disposition,'send');
  const pending=repair(command,f,randomUUID(),'changed@example.invalid');
  // Register rejection before releasing the competing order/send-fence locks.
  const rejection=assert.rejects(pending,/email_outcome_unresolved/);
  await gateway.query('COMMIT');await rejection;
  await command.query('BEGIN');
  await command.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
  await command.query('SET LOCAL ROLE authenticated');
  const {rows:[saved]}=await command.query('SELECT public.repair_order_email_client_sync_v1($1,$2,$3,$4,$5,$6,false,$7,$8) result',[f.order.id,f.email,f.order.state,f.order.email_payment_version,'changed@example.invalid',f.source,randomUUID(),f.fingerprint]);
  await command.query('COMMIT');assert.equal(saved.result.code,200);
  const {rows:[snapshot]}=await setup.query('SELECT recipient,workflow_state FROM public.email_messages WHERE message_id=$1',[f.source]);
  assert.deepEqual(snapshot,{recipient:f.email,workflow_state:'sending'});
 } finally {await gateway.query('ROLLBACK');await command.query('ROLLBACK');await Promise.all([setup.end(),gateway.end(),command.end()]);}
});


test('a deadline edit without a payment-version increment conflicts after acquiring the order lock',async()=>{
 const setup=await connect(),writer=await connect(),command=await connect();
 try {
  const f=await fixture(setup);
  const {rows:[pi]}=await setup.query("INSERT INTO eshop.payment_info(amount,paid,currency_code) VALUES(100,0,'CZK') RETURNING id");
  await setup.query('UPDATE eshop.orders SET payment_info=$2 WHERE id=$1',[f.order.id,pi.id]);
  f.fingerprint=(await setup.query('SELECT public.order_email_payment_fingerprint($1) token',[f.order.id])).rows[0].token;
  await writer.query('BEGIN');
  await writer.query('SELECT public.check_payment_info_is_mutable($1)',[pi.id]);
  await writer.query("UPDATE eshop.payment_info SET deadline=now()+interval '2 days' WHERE id=$1",[pi.id]);
  const pending=repair(command,f);await writer.query('COMMIT');
  assert.equal((await pending).code,409);
 } finally {await writer.query('ROLLBACK');await Promise.all([setup.end(),writer.end(),command.end()]);}
});
