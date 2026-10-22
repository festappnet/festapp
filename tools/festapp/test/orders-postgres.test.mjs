import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { randomUUID } from 'node:crypto';
import { fixture } from '../../../automation/authorization/benchmark.mjs';
import { openDisposableDatabase } from './postgres.mjs';
import { Operations } from '../src/operations/catalog.mjs';
import { orderDescriptors } from '../src/operations/orders.mjs';

test('order MCP executor uses real SQL owners for scoped reads, edits, products, payments, queueing and replay',
 {skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL},async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');
 assert.equal((await db.query('select bool_and(paused AND worker_url IS NULL) safe from email_capacity')).rows[0].safe,true);
 t.after(async()=>{await db.query('ROLLBACK');await db.end();});
 await db.query('SET LOCAL ROLE postgres');
 assert((await db.query("select to_regprocedure('public.can_read_orders(bigint)') present")).rows[0].present,'use the canonical authorization fixture');
 const stripe=(await db.query("select exists(select 1 from information_schema.columns where table_schema='eshop' and table_name='payment_info' and column_name='payment_method') present")).rows[0].present;
 if(!stripe) for(const migration of ['20261022160000_stripe_foundation.sql','20261022170000_stripe_connections.sql','20261022180000_stripe_checkout_ingest.sql']) {
  await db.query(await readFile(new URL('../../../supabase/migrations/'+migration,import.meta.url),'utf8'));
 }
 await db.query('SET LOCAL ROLE postgres');
 await db.query(await readFile(new URL('../../../supabase/migrations/20261022233000_operator_order_management.sql',import.meta.url),'utf8'));
 await db.query('RESET ROLE');
 const f=await fixture(db,1);
 const form=Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Order MCP form',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id",[f.occasion])).rows[0].id);
 const field=Number((await db.query("insert into form_fields(form,title,type) values($1,'Email','email') returning id",[form])).rows[0].id);
 const productType=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Admission','entry') returning id",[f.occasion])).rows[0].id);
 const product=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code,maximum) values($1,$2,'Admission',100,'CZK',100) returning id",[f.occasion,productType])).rows[0].id);
 const product2=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code,maximum) values($1,$2,'Dinner',50,'CZK',100) returning id",[f.occasion,productType])).rows[0].id);
 async function createOrder(state='ordered'){
  await db.query('RESET ROLE');
  const pi=Number((await db.query("insert into eshop.payment_info(amount,paid,returned,currency_code,variable_symbol,payment_method) values(200,0,0,'CZK',12345,'bank') returning id")).rows[0].id);
  const id=Number((await db.query("insert into eshop.orders(occasion,form,payment_info,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,$3,$4,200,'CZK',next_order_sequence($1),generate_order_symbol(),$5) returning id",[f.occasion,form,pi,state,{email:'buyer@example.invalid',name:'Test buyer',fields:[{[field]:'buyer@example.invalid'}],tickets:[]}])).rows[0].id);
  const tickets=[];
  for(let i=0;i<2;i++){
   const ticket=Number((await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,$2,gen_random_uuid()::text) returning id",[f.occasion,state])).rows[0].id);tickets.push(ticket);
   await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[id,product,ticket]);
  }
  await db.query("update eshop.orders set data=data||jsonb_build_object('tickets',$2::jsonb) where id=$1",[id,JSON.stringify(tickets.map(ticket=>({id:ticket,products:[{id:product,price:100}]})))]);
  await db.query('SET LOCAL ROLE authenticated');return {id,pi,tickets};
 }
 const a=await createOrder();const b=await createOrder();
 for(const signature of ['operator_order_revision_internal_v1(bigint)','operator_order_snapshot_internal_v1(bigint,boolean)','get_order_allowed_actions_internal_v1(bigint,jsonb)','check_operator_order_scope_internal_v1(bigint,bigint,bigint,boolean)']) assert.equal((await db.query("select has_function_privilege('authenticated',$1,'EXECUTE') allowed",['public.'+signature])).rows[0].allowed,false);
 const publicFns=['get_operator_order_report_v1(bigint,bigint,bigint)','get_operator_orders_v1(bigint,bigint,bigint,integer,bigint,text,text,bigint)','manage_operator_order_v1(bigint,bigint,bigint,bigint,uuid,text,text,jsonb)'];
 for(const signature of publicFns) assert.deepEqual((await db.query("select has_function_privilege('authenticated',$1,'EXECUTE') allowed,has_function_privilege('anon',$1,'EXECUTE') anon,has_function_privilege('service_role',$1,'EXECUTE') service",['public.'+signature])).rows[0],{allowed:true,anon:false,service:false});
 // The SQL adapter exercises the same executor and decoder as the remote tools.
 let loseNextResponse=false;
 const client={rpc:async(name,args)=>{
  await db.query('SAVEPOINT rpc');
  try{
   let sql,values;
   if(name==='get_operator_order_report_v1'){sql='select get_operator_order_report_v1($1,$2,$3) value';values=[args.p_occasion,args.p_organization,args.p_unit];}
   else if(name==='get_operator_orders_v1'){sql='select get_operator_orders_v1($1,$2,$3,$4,$5,$6,$7,$8) value';values=[args.p_occasion,args.p_organization,args.p_unit,args.p_limit,args.p_before,args.p_state,args.p_search,args.p_order];}
   else {assert.equal(name,'manage_operator_order_v1');sql='select manage_operator_order_v1($1,$2,$3,$4,$5,$6,$7,$8) value';values=[args.p_occasion,args.p_organization,args.p_unit,args.p_order,args.p_command_id,args.p_expected_revision,args.p_action,args.p_changes];}
   const data=(await db.query(sql,values)).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');
   if(loseNextResponse && name==='manage_operator_order_v1'){loseNextResponse=false;return {data:null,error:{code:'ECONNRESET',status:503}};}
   return {data,error:null};
  }catch(e){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return {data:null,error:{code:e.code,status:e.code==='42501'?403:400}};}
 }};
 const owner={root:'/tmp/festapp-orders-test',profile:{organizationId:f.org,tenantId:'fixture',name:'orders-fixture',backendOrigin:'http://127.0.0.1:61022'},allowedOperations:orderDescriptors.map(d=>d.id),
  authorized:action=>action(client,{userId:f.actor}),delegatedContext:async()=>({organizationId:f.org,unitId:f.unit})};
 const ops=new Operations(owner);
 const invoke=async(operation,args={})=>ops.invoke(operation,{occasionId:f.occasion,...args});
 const inspect=async id=>{const r=await invoke('orders.inspect',{orderId:id});assert.equal(r.ok,true,JSON.stringify(r));return r.data.orders[0];};
 let r=await invoke('orders.report');assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.report.valid.tickets.total,4);assert.equal(r.data.report.valid.orders.total,2);
 r=await invoke('orders.list',{limit:1});assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.orders.length,1);assert.equal(r.data.orders[0].id,b.id);assert.equal(r.data.nextCursor,b.id);
 r=await invoke('orders.list',{before:b.id,limit:1});assert.equal(r.data.orders[0].id,a.id);assert.equal(r.data.nextCursor,null);
 const admin=(await db.query('select get_orders($1::text,NULL::text,NULL::jsonb) value',[f.link])).rows[0].value;
 let row=await inspect(a.id);assert.deepEqual(admin.data.orders.find(o=>o.id===a.id).allowedActions,row.allowedActions);assert.equal(row.ticketCount,2);assert(!JSON.stringify(row).includes('ticket_symbol'));assert(!JSON.stringify(row).includes('requestSecret'));
 const note={orderId:a.id,commandId:randomUUID(),expectedRevision:row.revision,changes:{note:'Reviewed',responses:{[field]:'new@example.invalid'}}};
 r=await invoke('orders.update',note);assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.replayed,false);
 const repeated=await invoke('orders.update',note);assert.equal(repeated.ok,true,JSON.stringify(repeated));assert.equal(repeated.data.replayed,true);assert.equal(repeated.data.revision,r.data.revision);
 assert.equal((await inspect(a.id)).customer.email,'new@example.invalid');
 r=await invoke('orders.update',{...note,commandId:randomUUID(),changes:{note:'Stale'}});assert.equal(r.error.code,'ORDER_CHANGED_RELOAD_REQUIRED');
 assert.equal((await invoke('orders.update',{...note,changes:{note:'Reused UUID with different content'}})).ok,false);
 row=await inspect(a.id);
 r=await invoke('orders.update',{orderId:a.id,commandId:randomUUID(),expectedRevision:row.revision,changes:{tickets:[{ticketId:a.tickets[0],products:[{productId:product,price:'100'},{productId:product2,price:'50'}]}]}});assert.equal(r.ok,true,JSON.stringify(r));
 assert.equal((await inspect(a.id)).price,'250.00');
 row=await inspect(a.id);const payment={orderId:a.id,commandId:randomUUID(),expectedRevision:row.revision,amount:'250.00',currency:'CZK',receivedAt:'2026-10-22T18:00:00Z'};
 loseNextResponse=true;r=await invoke('payments.record',payment);assert.equal(r.ok,false);assert.equal(r.error.retryable,true);
 r=await invoke('payments.record',payment);assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.replayed,true);
 assert.equal((await inspect(a.id)).state,'paid');
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) n from eshop.transactions where payment_info=$1',[a.pi])).rows[0].n),1);await db.query('SET LOCAL ROLE authenticated');
 row=await inspect(a.id);const send={orderId:a.id,commandId:randomUUID(),expectedRevision:row.revision};
 r=await invoke('orders.send_tickets',send);assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.delivery,'queued');
 const message=r.data.messageId;assert.equal((await invoke('orders.send_tickets',send)).data.messageId,message);
 await db.query('RESET ROLE');const queued=(await db.query('select recipient from email_messages where message_id=$1',[message])).rows[0];assert.equal(queued.recipient,'new@example.invalid');await db.query('SET LOCAL ROLE authenticated');
 row=await inspect(b.id);r=await invoke('orders.mark_paid',{orderId:b.id,commandId:randomUUID(),expectedRevision:row.revision});assert.equal(r.ok,true,JSON.stringify(r));assert.equal((await inspect(b.id)).state,'paid');
 row=await inspect(b.id);const cancel={orderId:b.id,commandId:randomUUID(),expectedRevision:row.revision};r=await invoke('orders.cancel',cancel);assert.equal(r.ok,true,JSON.stringify(r));assert.equal((await invoke('orders.cancel',cancel)).data.replayed,true);assert.equal((await inspect(b.id)).state,'storno');
 r=await invoke('orders.report');assert.equal(r.ok,true,JSON.stringify(r));assert.equal(r.data.report.valid.tickets.total,2);
 // Currency and manager checks still belong to the canonical payment owner.
 row=await inspect(a.id);
 const extra={orderId:a.id,commandId:randomUUID(),expectedRevision:row.revision,amount:'1.00',currency:'EUR',receivedAt:'2026-10-22T18:00:00Z'};
 assert.equal((await invoke('payments.record',extra)).ok,false);
 await db.query('RESET ROLE');await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await invoke('payments.record',{...extra,commandId:randomUUID(),currency:'CZK'})).ok,false);
 // A known order ID does not authorize another event or organizer.
 const scope=owner.delegatedContext;owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+999999});assert.equal((await invoke('orders.inspect',{orderId:a.id})).error.code,'FORBIDDEN');owner.delegatedContext=scope;
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await invoke('orders.inspect',{orderId:a.id})).error.code,'FORBIDDEN');assert.equal((await invoke('payments.record',payment)).error.code,'FORBIDDEN');
});
