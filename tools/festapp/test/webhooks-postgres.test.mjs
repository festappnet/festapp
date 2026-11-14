import test from 'node:test';
import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { fixture as formFixture, input } from './form-completion-fixtures.mjs';
import { options, denied } from './form-fixtures.mjs';
import { setup as apiSetup, connect, apiRequest } from './api-fixture.mjs';
import { profile, reply } from './fixture.mjs';
import { webhookDescriptors, webhookBinding } from '../src/operations/webhooks.mjs';
import { createWebhookWorker, webhookDispatchOwner } from '../src/remote/webhook-worker.mjs';
import { WEBHOOK_TYPES } from '../src/remote/webhook-protocol.mjs';
import { READ_SCOPE } from '../src/remote/config.mjs';
import { webhookReceiver } from './webhook-tls-fixture.mjs';
const scopes=[READ_SCOPE,'festapp:orders:read','festapp:webhooks:read','festapp:webhooks:write'];

async function setup(t){
 const s=await formFixture(t),{db,f}=s;
 let drop=false;const errors=[];
 const remote=await apiSetup(t,{userId:f.actor,profileValue:profile(undefined,f.org),apiPolicy:{
  allowedScopes:scopes,allowedOperations:['context.inspect','access.inspect',...webhookDescriptors.map(d=>d.id)]},
  fetchImpl:async(url,init)=>{
   if(!url.pathname.startsWith('/rest/v1/rpc/'))return;
   const name=url.pathname.split('/').at(-1);
   if(!['integration_webhook_api_v1','get_operator_access_v1'].includes(name))return;
   await db.query('SAVEPOINT rpc');
   try{
    const args=JSON.parse(init.body),keys=Object.keys(args);
    const data=(await db.query('select '+name+'('+keys.map((n,i)=>n+'=> $'+(i+1)).join(',')+') value',Object.values(args))).rows[0].value;
    await db.query('RELEASE SAVEPOINT rpc');
    if(drop&&name==='integration_webhook_api_v1'){drop=false;return reply({code:'fixture_drop'},503);}
    return reply(data);
   }catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');errors.push({name,code:error.code,message:error.message});return reply({code:error.code,message:error.message},error.code==='42501'?403:400);}
  }});
 await db.query('SET LOCAL ROLE authenticated');
 const {tokens}=await connect(remote,{scope:scopes.join(' '),occasionIds:[String(f.occasion)]});
 async function call(operation,args,status=200){const r=await apiRequest(remote,tokens,'webhooks.'+operation,{occasionId:f.occasion,...args});const body=await r.json();assert.equal(r.status,status,JSON.stringify({body,errors}));return body;}
 return{...s,remote,tokens,call,errors,drop:()=>{drop=true;}};
}
async function checkout(s,{command=randomUUID(),email='jana-'+randomUUID()+'@example.invalid',extra={}}={}){
 const {db,f,made}=s;
 await db.query('RESET ROLE');
 await db.query('update forms set is_open=true where id=$1',[made.formId]);
 const key=(await db.query('select key from forms where id=$1',[made.formId])).rows[0].key;
 const order={...input(s,email),...extra,form:key,payment_method:'bank'};
 // Actual anonymous public checkout, not a fabricated outbox row.
 await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','anon',true)");
 await db.query('SET LOCAL ROLE anon');
 const value=(await db.query('select create_ticket_order_client_sync_v1($1,$2,$3) value',[order,command,randomUUID()])).rows[0].value;
 await db.query('RESET ROLE');
 await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
 await db.query('SET LOCAL ROLE authenticated');
 assert.equal(value.code,200,JSON.stringify(value));return value;
}
const creation=(s,extra={})=>({commandId:randomUUID(),expectedContractVersion:1,eventTypes:[WEBHOOK_TYPES.orderCreated],url:'https://hooks.example.com/festapp',formId:s.made.formId,...extra});

test('real API/OAuth -> anonymous checkout -> durable SQL -> signed TLS, retry, redelivery, rotation, pause and deletion',options,async t=>{
 const s=await setup(t),sink=await webhookReceiver(t),{db,remote,call}=s;
 const args=creation(s),created=(await call('create',args)).data;
 assert.match(created.signingSecret,/^whsec_/);const sid=created.subscription.id;
 assert.equal((await call('create',args)).data.signingSecret,created.signingSecret);
 assert.equal((await call('list',{})).data.subscriptions.length,1);
 await db.query('RESET ROLE');
 const ticketField=Number((await db.query("insert into form_fields(form,title,type,is_ticket_field,is_hidden) values($1,'Stravování','text',true,false) returning id",[s.made.formId])).rows[0].id);
 await db.query('SET LOCAL ROLE authenticated');
 const emailField=s.made.authoring.fields.find(x=>x.type==='email'),customerEmail='jana-'+randomUUID()+'@example.invalid';
 const initial=await checkout(s,{email:customerEmail,extra:{private_token:'never-in-public-event',phone:'+420777123456',fields:[{[emailField.id]:customerEmail}],ticket:input(s).ticket.map(x=>({...x,fields:[...x.fields,{[ticketField]:'Bezlepková strava'}]}))}});const orderId=Number(initial.data.order.id);
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*) n from integration_webhook_events where order_id=$1',[orderId])).rows[0].n,'1');
 // Duplicate producer invocation cannot duplicate the durable fact or recipient.
 await db.query('select emit_order_webhook_internal($1)',[orderId]);
 assert.equal((await db.query('select count(*) n from integration_webhook_deliveries where subscription=$1',[sid])).rows[0].n,'1');
 await db.query('SET LOCAL ROLE authenticated');
 const audit=[];const worker=createWebhookWorker({config:remote.config,storage:remote.storage,fetchImpl:remote.owner.fetch,send:sink.send,audit:x=>audit.push(x)});t.after(()=>worker.close());
 sink.status(503);await worker.drain();assert.equal(sink.receipts.length,1,JSON.stringify({audit,errors:s.errors}));sink.verify(sink.receipts[0],created.signingSecret);
 const snapshot=sink.receipts[0].body,ev=JSON.parse(snapshot);assert.equal(ev.data.orderId,orderId);assert.equal(ev.data.customer.email,customerEmail);assert.equal(ev.data.customer.phone,'+420777123456');assert(!snapshot.includes('ticket_symbol'));assert(!snapshot.includes('private_token'));assert(!snapshot.includes('never-in-public-event'));assert.equal(ev.data.responses[0][String(emailField.id)],customerEmail);assert.equal(ev.data.tickets[0].responses[0][String(ticketField)],'Bezlepková strava');
 await db.query('RESET ROLE');
 await db.query("update eshop.orders set data=data||'{\"email\":\"changed@example.invalid\"}'::jsonb where id=$1",[orderId]);
 await db.query('update integration_webhook_deliveries set next_due=clock_timestamp() where subscription=$1',[sid]);await db.query('SET LOCAL ROLE authenticated');
 sink.status(202);await worker.drain();assert.equal(sink.receipts.length,2,JSON.stringify({audit,errors:s.errors}));assert.equal(sink.receipts[1].body,snapshot);assert.equal(sink.receipts[1].headers['webhook-id'],sink.receipts[0].headers['webhook-id']);
 let history=(await call('deliveries',{subscriptionId:sid})).data.deliveries;assert.equal(history[0].state,'succeeded');assert.equal(history[0].attempts,2);assert.equal(history[0].history.length,2);assert(!JSON.stringify(history).includes(customerEmail));
 const retryArgs={subscriptionId:sid,deliveryId:history[0].id,commandId:randomUUID()};await call('redeliver',retryArgs);await call('redeliver',retryArgs);await worker.drain();assert.equal(sink.receipts.length,3);assert.equal(sink.receipts[2].body,snapshot);
 const rotated=(await call('rotate_secret',{subscriptionId:sid,commandId:randomUUID(),expectedVersion:1})).data;assert.notEqual(rotated.signingSecret,created.signingSecret);assert.equal(rotated.subscription.version,2);
 const testArgs={subscriptionId:sid,commandId:randomUUID()};await call('test',testArgs);await call('test',testArgs);await worker.drain();assert.equal(sink.receipts.length,4);assert.equal(JSON.parse(sink.receipts[3].body).type,WEBHOOK_TYPES.test);sink.verify(sink.receipts[3],rotated.signingSecret);sink.verify(sink.receipts[3],created.signingSecret);
 const paused=(await call('update',{subscriptionId:sid,expectedVersion:2,commandId:randomUUID(),state:'paused'})).data;assert.equal(paused.subscription.version,3);
 await checkout(s,{email:'paused@example.invalid'});await worker.drain();assert.equal(sink.receipts.length,4);
 await call('update',{subscriptionId:sid,expectedVersion:3,commandId:randomUUID(),state:'active'});
 await call('delete',{subscriptionId:sid,expectedVersion:4,commandId:randomUUID()});assert.equal((await call('list',{})).data.subscriptions.length,0);
 await call('create',args,403);assert.equal(audit.some(x=>JSON.stringify(x).includes('example.com')),false);
});

test('SQL-response loss reconciles the same encrypted key/intent; stale version and changed command cannot mutate',options,async t=>{
 const s=await setup(t),args=creation(s);s.drop();await s.call('create',args,503);
 const intents=s.remote.storage.values('WebhookCommand');assert.equal(intents.length,1);const key=intents[0].config.secrets[0].key;
 const replay=(await s.call('create',args)).data;assert.equal(replay.signingSecret,key);assert.equal(replay.replayed,true);
 await s.call('create',{...args,url:'https://hooks.example.com/changed'},422);
 const target={subscriptionId:replay.subscription.id,expectedVersion:99,commandId:randomUUID(),state:'paused'};
 await s.call('update',target,409);
 // A known rejected conflict leaves the existing subscription usable. Only an
 // uncertain transport outcome retains its pending-command dispatch fence.
 assert.equal(s.remote.storage.values('WebhookSubscription')[0].pendingCommand,undefined);
});

test('live rights, tenant/resource binding and private table ACLs fence dispatch and command replay',options,async t=>{
 const s=await setup(t),{db,f}=s,created=(await s.call('create',creation(s))).data;
 for(const table of ['integration_webhook_events','integration_webhook_subscriptions','integration_webhook_deliveries','integration_webhook_commands'])
  for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query('select has_table_privilege($1,$2,\'SELECT\') allowed',[role,'public.'+table])).rows[0].allowed,false);
 await checkout(s);
 const grant=s.remote.storage.values('Delegation')[0],owner=webhookDispatchOwner(s.remote.config,s.remote.storage,grant,{fetchImpl:s.remote.owner.fetch}),binding=webhookBinding(owner);
 await denied(db,'select integration_webhook_api_v1($1,$2,$3,$4,\'claim\',$5)',[f.occasion,f.org+1,f.unit,binding,{subscriptionId:created.subscription.id}]);
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_order=false,is_editor_order_view=false,is_manager=false,is_editor=false,is_editor_view=false where occasion=$1',[f.occasion]);await db.query('update unit_users set is_manager=false,is_editor=false,is_editor_view=false where unit=$1',[f.unit]);await db.query('SET LOCAL ROLE authenticated');
 let sent=0;const worker=createWebhookWorker({config:s.remote.config,storage:s.remote.storage,fetchImpl:s.remote.owner.fetch,send:async()=>{sent++;return {status:202};}});await worker.drain();await worker.close();assert.equal(sent,0);
 await s.call('list',{},403);
});

test('real SQL leases serialize claimants, recover after restart, reject stale completion and hide uncommitted/rolled-back events',options,async t=>{
 const s=await formFixture(t),{db,f}=s,binding='a'.repeat(64),sid=randomUUID();
 const params=[f.occasion,f.org,f.unit,binding];
 const rpc=async(c,action,args)=>(await c.query('select integration_webhook_api_v1($1,$2,$3,$4,$5,$6) value',[...params,action,{subscriptionId:sid,...args}])).rows[0].value;
 await rpc(db,'create',{commandId:randomUUID(),expiresAt:new Date(Date.now()+86400000).toISOString(),formId:s.made.formId});
 const first=await checkout(s);await db.query('COMMIT');
 const {openDisposableDatabase}=await import('./postgres.mjs');
 const a=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL),b=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 t.after(async()=>{await a.query('ROLLBACK');await b.query('ROLLBACK');await a.end();await b.end();});
 async function begin(c){await c.query('BEGIN');await c.query("SET LOCAL statement_timeout='5s'");await c.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);await c.query('SET LOCAL ROLE authenticated');}
 await begin(a);const one=await rpc(a,'claim',{});assert(one.id);
 await begin(b);const competing=rpc(b,'claim',{});await a.query('COMMIT');assert.deepEqual(await competing,{});await b.query('COMMIT');
 await db.query('BEGIN');await db.query('RESET ROLE');await db.query("update integration_webhook_deliveries set lease_until=clock_timestamp()-interval '1 second' where id=$1",[one.id]);await db.query('COMMIT');
 await begin(b);const recovered=await rpc(b,'claim',{});assert.equal(recovered.id,one.id);assert.notEqual(recovered.lease,one.lease);assert.equal(recovered.attempt,2);await b.query('COMMIT');
 await begin(a);const stale=await rpc(a,'complete',{deliveryId:one.id,lease:one.lease,state:'succeeded',httpStatus:202,errorCategory:null,nextDue:null});assert.equal(stale.completed,false);await a.query('COMMIT');
 await begin(b);assert.equal((await rpc(b,'complete',{deliveryId:one.id,lease:recovered.lease,state:'succeeded',httpStatus:202,errorCategory:null,nextDue:null})).completed,true);await b.query('COMMIT');
 await db.query('BEGIN');const uncommitted=await checkout(s);const newOrder=Number(uncommitted.data.order.id);
 await begin(a);assert.deepEqual(await rpc(a,'claim',{}),{});await a.query('COMMIT');
 await db.query('COMMIT');await begin(a);const visible=await rpc(a,'claim',{});assert.equal(JSON.parse(visible.body).data.orderId,newOrder);await a.query('COMMIT');
 await db.query('BEGIN');await db.query('select id from forms where id=$1 for update',[s.made.formId]);
 await begin(a);const registering=a.query('select integration_webhook_api_v1($1,$2,$3,$4,\'create\',$5) value',[...params,{subscriptionId:randomUUID(),commandId:randomUUID(),formId:s.made.formId,expiresAt:new Date(Date.now()+86400000).toISOString()}]);
 // Give the contender a chance to wait on the already-held form lock.
 await new Promise(resolve=>setTimeout(resolve,30));
 await checkout(s);await db.query('COMMIT');assert((await registering).rows[0].value.subscription);await a.query('COMMIT');
 await db.query('BEGIN');await db.query("update integration_webhook_deliveries set state='pending',lease=null,lease_until=null,attempts=16,next_due='2000-01-01' where id=$1",[visible.id]);await db.query('COMMIT');
 await begin(a);assert.deepEqual(await rpc(a,'claim',{}),{});await a.query('COMMIT');
 assert.equal((await db.query('select state from integration_webhook_deliveries where id=$1',[visible.id])).rows[0].state,'exhausted');
 await db.query('BEGIN');await db.query("update integration_webhook_deliveries set state='pending',attempts=1,first_attempt_at=clock_timestamp()-interval '73 hours',next_due='2000-01-01' where id=$1",[visible.id]);await db.query('COMMIT');
 await begin(a);assert.deepEqual(await rpc(a,'claim',{}),{});await a.query('COMMIT');
 assert.equal((await db.query('select state from integration_webhook_deliveries where id=$1',[visible.id])).rows[0].state,'exhausted');
 await db.query('BEGIN');const rolled=await checkout(s);const rolledId=Number(rolled.data.order.id);await db.query('ROLLBACK');
 assert.equal((await db.query('select count(*) n from integration_webhook_events where order_id=$1',[rolledId])).rows[0].n,'0');
 // Mechanical FK deletion removes the private snapshot and makes replay impossible.
 await begin(db);await db.query('select delete_order_client_sync_v1($1,$2)',[Number(first.data.order.id),randomUUID()]);await db.query('COMMIT');
 assert.equal((await db.query('select count(*) n from integration_webhook_events where order_id=$1',[Number(first.data.order.id)])).rows[0].n,'0');
 await begin(b);await denied(b,'select integration_webhook_api_v1($1,$2,$3,$4,\'redeliver\',$5)',[...params,{subscriptionId:sid,commandId:randomUUID(),deliveryId:one.id}],'22023');await b.query('COMMIT');
});

test('retention does not depend on live consent; 410 disables, expiry and attempt bounds prevent more sends',options,async t=>{
 const s=await setup(t),{db}=s,created=(await s.call('create',creation(s))).data,sid=created.subscription.id;
 await s.call('test',{subscriptionId:sid,commandId:randomUUID()});
 const sink=await webhookReceiver(t);sink.status(410);
 const worker=createWebhookWorker({config:s.remote.config,storage:s.remote.storage,fetchImpl:s.remote.owner.fetch,send:sink.send});await worker.drain();await worker.drain();await worker.close();assert.equal(sink.receipts.length,1);
 const disabled=(await s.call('list',{})).data.subscriptions[0];assert.equal(disabled.state,'disabled');
 await s.call('update',{subscriptionId:sid,commandId:randomUUID(),expectedVersion:disabled.version,state:'paused'});
 await db.query('RESET ROLE');await db.query("update integration_webhook_events set created_at=clock_timestamp()-interval '8 days' where id in (select event from integration_webhook_deliveries where subscription=$1)",[sid]);
 await db.query("update integration_webhook_deliveries set state='pending' where subscription=$1",[sid]);
 await db.query('select purge_integration_webhooks_internal()');assert.equal((await db.query('select body from integration_webhook_events where id in(select event from integration_webhook_deliveries where subscription=$1)',[sid])).rows[0].body,null);
 assert.equal((await db.query('select state from integration_webhook_deliveries where subscription=$1',[sid])).rows[0].state,'exhausted');
 await db.query('SET LOCAL ROLE authenticated');const active=(await s.call('list',{})).data.subscriptions[0];await s.call('update',{subscriptionId:sid,commandId:randomUUID(),expectedVersion:active.version,state:'active'});await s.call('redeliver',{subscriptionId:sid,commandId:randomUUID(),deliveryId:(await s.call('deliveries',{subscriptionId:sid})).data.deliveries[0].id},422);
});

test('restart after HTTPS acceptance recovers the encrypted key and retries the same delivery; revocation removes dispatch material',options,async t=>{
 const s=await setup(t),{db,remote}=s,sink=await webhookReceiver(t),created=(await s.call('create',creation(s))).data;
 await checkout(s);
 let closed,worker;
 worker=createWebhookWorker({config:remote.config,storage:remote.storage,fetchImpl:remote.owner.fetch,send:async args=>{const result=await sink.send(args);closed=worker.close();return result;}});
 await worker.drain();await closed;assert.equal(sink.receipts.length,1);
 const {readFile}=await import('node:fs/promises');const {join}=await import('node:path');
 const bytes=await readFile(join(remote.root,'remote.sqlite'));assert.equal(bytes.includes(Buffer.from(created.signingSecret)),false);
 await remote.storage.close();
 const {openRemoteStorage}=await import('../src/remote/storage.mjs');const storage=await openRemoteStorage(remote.root,remote.key);
 try{
  assert.equal(storage.values('WebhookSubscription')[0].secrets[0].key,created.signingSecret);
  await db.query('RESET ROLE');await db.query("update integration_webhook_deliveries set lease_until=clock_timestamp()-interval '1 second' where subscription=$1",[created.subscription.id]);await db.query('SET LOCAL ROLE authenticated');
  const restarted=createWebhookWorker({config:remote.config,storage,fetchImpl:remote.owner.fetch,send:sink.send});await restarted.drain();await restarted.close();
  assert.equal(sink.receipts.length,2);assert.equal(sink.receipts[1].body,sink.receipts[0].body);assert.equal(sink.receipts[1].headers['webhook-id'],sink.receipts[0].headers['webhook-id']);sink.verify(sink.receipts[1],created.signingSecret);
  const grant=storage.values('Delegation')[0];storage.revoke(grant.id);assert.equal(storage.values('WebhookSubscription').length,0);assert.equal(storage.values('WebhookCommand').length,0);
 }finally{await storage.close();}
});

test('pending intent reconciles automatically and expired consent never dispatches',options,async t=>{
 const s=await setup(t),args=creation(s);s.drop();await s.call('create',args,503);
 const sink=await webhookReceiver(t),worker=createWebhookWorker({config:s.remote.config,storage:s.remote.storage,fetchImpl:s.remote.owner.fetch,send:sink.send});
 await worker.drain();assert.equal(s.remote.storage.values('WebhookCommand')[0].phase,'completed');assert.equal(s.remote.storage.values('WebhookSubscription')[0].pendingCommand,undefined);
 await checkout(s);const grant=s.remote.storage.values('Delegation')[0];s.remote.storage.putUntil('Delegation',grant.id,{...grant,expiresAt:Date.now()-1000},Date.now()+60000);
 await worker.drain();await worker.close();assert.equal(sink.receipts.length,0);
 await s.call('list',{},401);
});

test('100000-row durable backlog enforces atomic backpressure at the configured organization cap',options,async t=>{
 const s=await formFixture(t),{db,f,made}=s,sid=randomUUID();
 await db.query('select integration_webhook_api_v1($1,$2,$3,$4,\'create\',$5)',[f.occasion,f.org,f.unit,'b'.repeat(64),{subscriptionId:sid,commandId:randomUUID(),formId:made.formId,expiresAt:new Date(Date.now()+86400000).toISOString()}]);
 await db.query('update forms set is_open=true where id=$1',[made.formId]);
 const start=performance.now();
 await db.query("insert into integration_webhook_events(organization,occasion,event_type,body) select $1,$2,'net.festapp.webhook.test.v1','{}' from generate_series(1,100000)",[f.org,f.occasion]);
 await db.query('insert into integration_webhook_deliveries(subscription,event) select $1,id from integration_webhook_events where organization=$2',[sid,f.org]);
 const key=(await db.query('select key from forms where id=$1',[made.formId])).rows[0].key;
 const result=(await db.query('select create_ticket_order_client_sync_v1($1,$2,$3) value',[{...input(s),form:key,payment_method:'bank'},randomUUID(),randomUUID()])).rows[0].value;
 assert.notEqual(result.code,200);assert.match(result.message??result.data?.message??'',/backlog capacity exhausted/,JSON.stringify({code:result.code,errorCode:result.errorCode,error:result.error}));
 assert.equal((await db.query('select count(*) n from eshop.orders where form=$1',[made.formId])).rows[0].n,'0');
 assert.equal((await db.query('select count(*) n from integration_webhook_deliveries where subscription=$1',[sid])).rows[0].n,'100000');
 t.diagnostic('100000-row backlog fixture and atomic rejection: '+Math.round(performance.now()-start)+' ms');
});

test('idle dispatch avoids per-tick cleanup and paused/expired subscriptions make no backend calls',options,async t=>{
 const s=await setup(t),created=(await s.call('create',creation(s))).data,sid=created.subscription.id;
 const calls=[];
 const worker=createWebhookWorker({config:s.remote.config,storage:s.remote.storage,fetchImpl:async(url,init)=>{
  const location=new URL(url.url??url);
  calls.push({path:location.pathname,action:location.pathname.endsWith('/integration_webhook_api_v1')?JSON.parse(init.body).p_action:undefined});
  return s.remote.owner.fetch(url,init);
 }});t.after(()=>worker.close());
 await worker.drain();assert.deepEqual(calls.filter(c=>c.action).map(c=>c.action),['claim']);
 await s.call('update',{subscriptionId:sid,expectedVersion:1,commandId:randomUUID(),state:'paused'});
 calls.length=0;await worker.drain();assert.equal(calls.length,0,'paused endpoint must not refresh backend credentials or poll SQL');
 await s.call('update',{subscriptionId:sid,expectedVersion:2,commandId:randomUUID(),state:'active'});
 calls.length=0;await worker.drain();assert.deepEqual(calls.filter(c=>c.action).map(c=>c.action),['claim']);
 const local=s.remote.storage.values('WebhookSubscription')[0];
 s.remote.storage.putUntil('WebhookSubscription',local.binding+':'+local.id,{...local,expiresAt:Date.now()-1000},Date.now()+60000);
 calls.length=0;await worker.drain();assert.equal(calls.length,0,'expired endpoint must not refresh backend credentials or poll SQL');
});
