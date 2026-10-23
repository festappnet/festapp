import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setup,paidAtomicSwap,executor} from './seat-fixtures.mjs';
import {openDisposableDatabase} from './postgres.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function bank(s){await s.db.query('RESET ROLE');const id=Number((await s.db.query("insert into eshop.bank_accounts(title,type,supported_currencies,account_number,account_number_human_readable) values('Local order fixture','FIO',array['CZK'],'CZ6508000000192000145399','19-2000145399/0800') returning id")).rows[0].id);await s.db.query('insert into eshop.unit_bank_accounts(unit,bank_account) values($1,$2)',[s.f.unit,id]);await s.db.query('SET LOCAL ROLE authenticated');}
async function preview(s,ids,input=null,diagnose=true){const f=s.f;const value=(await s.db.query('select preview_blueprint_seat_order($1,$2,$3,$4,$5,$6) v',[f.occasion,f.org,f.unit,f.blueprint,ids,input])).rows[0].v;
 if(input&&value.code!==200&&diagnose){await s.db.query('RESET ROLE');await s.db.query('SAVEPOINT explain_quote');try{await s.db.query('select blueprint_seat_order_quote_internal(apply_blueprint_seat_order_internal(blueprint_seat_order_selection_internal($1,$2,$3,1000),$4,$5))',[f.occasion,f.blueprint,ids,input,randomUUID()]);}catch(e){throw new Error('Actual quote owner: '+e.message+'; '+(e.detail??'')+'; '+(e.where??''));}finally{await s.db.query('ROLLBACK TO SAVEPOINT explain_quote');await s.db.query('RELEASE SAVEPOINT explain_quote');await s.db.query('SET LOCAL ROLE authenticated');}}
 return value;}
async function apply(s,p,input,command=randomUUID(),editor=false){const f=s.f;return(await s.db.query('select create_blueprint_seat_order($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) v',[f.occasion,f.org,f.unit,f.blueprint,p.requestedSpotIds,input,p.quote.spotIds,p.quote.affectedSpotIds,JSON.stringify(p.quote.blueprints),p.confirmationHash,command,editor,p.actorId])).rows[0].v;}
async function state(s){await s.db.query('RESET ROLE');const r=(await s.db.query(`select jsonb_build_object(
 'orders',(select coalesce(jsonb_agg(to_jsonb(o) order by id),'[]') from eshop.orders o where occasion=$1),
 'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from eshop.payment_info p where id in(select payment_info from eshop.orders where occasion=$1)),
 'tickets',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from eshop.tickets t where occasion=$1),
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by id),'[]') from eshop.order_product_ticket i where "order" in(select id from eshop.orders where occasion=$1)),
 'spots',(select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') from eshop.spots s where occasion=$1),
 'history',(select coalesce(jsonb_agg(to_jsonb(h) order by id),'[]') from eshop.orders_history h where "order" in(select id from eshop.orders where occasion=$1)),
 'email',(select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') from email_messages e where occasion=$1)) v`,[s.f.occasion])).rows[0].v;await s.db.query('SET LOCAL ROLE authenticated');return r;}

test('a changed actor cannot claim the approved seat-order UUID; the original actor can still execute it',options,async t=>{
 const s=await setup(t);await bank(s);
 const input={email:'actor-fence@example.invalid',form_key:s.fx.formKey},p=await preview(s,[s.bindings[0].spotId],input),command=randomUUID();
 const before=await state(s);
 await s.db.query('SAVEPOINT changed_actor');
 await s.db.query("select set_config('request.jwt.claim.sub',$1,true)",[randomUUID()]);
 await assert.rejects(apply(s,p,input,command),error=>error.code==='42501');
 await s.db.query('ROLLBACK TO SAVEPOINT changed_actor');await s.db.query('RELEASE SAVEPOINT changed_actor');
 assert.deepEqual(await state(s),before);
 await s.db.query('RESET ROLE');
 assert.equal(Number((await s.db.query('select count(*) n from client_mutation_receipts where command_id=$1',[command])).rows[0].n),0);
 await s.db.query('SET LOCAL ROLE authenticated');
 const done=await apply(s,p,input,command);assert.equal(done.status,'applied',JSON.stringify(done));
});

test('changed bank recipient invalidates approval and rolls back allocation, cancellation and delivery together',options,async t=>{
 const s=await paidAtomicSwap(t);await bank(s);
 const input={email:'changed-bank@example.invalid',form_key:s.fx.formKey},p=await preview(s,[s.first],input);
 await s.db.query('RESET ROLE');
 await s.db.query("update eshop.bank_accounts set account_number='CZ6508000000192000145400' where id in(select bank_account from eshop.unit_bank_accounts where unit=$1)",[s.f.unit]);
 await s.db.query('SET LOCAL ROLE authenticated');
 const before=await state(s),done=await apply(s,p,input);
 assert.equal(done.status,'rejected',JSON.stringify(done));assert.equal(done.data.reason,'BLUEPRINT_ORDER_CHANGED');
 assert.deepEqual(await state(s),before);
});

test('seat-order requirements and final quote expand a full unit; real creation and email intent roll back until one confirmed receipt',options,async t=>{
 const s=await setup(t);await bank(s);const ids=[s.bindings[0].spotId],input={email:'new-order@example.invalid',form_key:s.fx.formKey};
 const requirements=await preview(s,ids);assert.equal(requirements.mode,'requirements');assert.equal(requirements.spotIds.length,2);assert.equal(requirements.formKey,s.fx.formKey);
 const before=await state(s),p=await preview(s,ids,input);assert.equal(p.code,200,JSON.stringify(p));assert.equal(p.mode,'quote');assert.equal(p.quote.newOrder.amount,'200.00');assert.equal(p.quote.newOrder.ticketCount,2);
 assert.deepEqual(await state(s),before,'quote leaves no tickets/order/payment/history/email effects');assert.equal((await preview(s,ids,input)).confirmationHash,p.confirmationHash,'allocated IDs and sequence gaps never invalidate stable approval');
 const command=randomUUID(),done=await apply(s,p,input,command);assert.equal(done.status,'applied',JSON.stringify(done));assert.equal(done.sync,undefined);assert.equal(done.data.quote.newOrder.amount,'200.00');assert.equal(done.data.order,undefined,'MCP boundary omits full customer/payment payload');
 const after=await state(s);assert.equal(after.orders.length,1);assert.equal(after.tickets.length,2);assert.equal(after.email.length,1);assert.deepEqual(await apply(s,p,input,command),done);assert.deepEqual(await state(s),after,'replay cannot replace the new order again');
 const stale=await apply(s,p,input);assert.equal(stale.status,'rejected');assert.deepEqual(await state(s),after,'stale replacement cannot cancel the later order');
});

test('seat-order quote shows actual partial cancellation and preserves unselected tickets and original received money',options,async t=>{
 const s=await paidAtomicSwap(t);await bank(s);await s.db.query('RESET ROLE');
 const ticket=Number((await s.db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[s.f.occasion])).rows[0].id);
 await s.db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3)',[s.order,ticket,s.fx.product]);
 await s.db.query("update eshop.orders set price=300,data=jsonb_set(data,'{tickets}',data->'tickets'||jsonb_build_array(jsonb_build_object('id',$2::bigint,'products',jsonb_build_array(_swap_spots_generate_product_json($3,NULL))))) where id=$1",[s.order,ticket,s.fx.product]);await s.db.query('update eshop.payment_info set amount=300,paid=300 where id=$1',[s.payment]);await s.db.query('SET LOCAL ROLE authenticated');
 const input={email:'replacement@example.invalid',form_key:s.fx.formKey},before=await state(s),p=await preview(s,[s.first],input);assert.equal(p.code,200,JSON.stringify(p));assert.deepEqual(p.quote.orders,[{orderId:s.order,beforeAmount:'300.00',afterAmount:'100.00',delta:'-200.00',currencyCode:'CZK',beforeState:'paid',afterState:'paid'}]);assert.deepEqual(await state(s),before);
 const done=await apply(s,p,input);assert.equal(done.status,'applied',JSON.stringify(done));const after=await state(s),old=after.orders.find(o=>Number(o.id)===s.order);assert.equal(Number(old.price),100);assert.equal(old.data.tickets.length,1);assert.equal(Number(old.data.tickets[0].id),ticket);assert.equal(Number(after.payments.find(p=>Number(p.id)===s.payment).paid),300,'this operation never invents an external refund');
});

test('replacing one seat shows and locks every other seat released by the same old ticket without duplicating its conflict',options,async t=>{
 const {paidSwap}=await import('./seat-fixtures.mjs');const s=await paidSwap(t);await bank(s);await s.db.query('RESET ROLE');
 const item=Number((await s.db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[s.order,s.ticket,s.fx.product])).rows[0].id);
 await s.db.query('update eshop.spots set order_product_ticket=$2 where id=$1',[s.second,item]);
 await s.db.query("update eshop.orders set price=200,data=jsonb_set(data,'{tickets,0,products}',data#>'{tickets,0,products}'||jsonb_build_array(_swap_spots_generate_product_json($2,$3))) where id=$1",[s.order,s.fx.product,s.second]);await s.db.query('update eshop.payment_info set amount=200,paid=200 where id=$1',[s.payment]);await s.db.query('SET LOCAL ROLE authenticated');
 const input={email:'new-owner@example.invalid',form_key:s.fx.formKey},requirements=await preview(s,[s.first]);assert.equal(requirements.conflicts.length,1);const both=await preview(s,[s.first,s.second]);assert.equal(both.conflicts.length,1,'one original ticket is never duplicated by its two seat bindings');assert.deepEqual(both.conflicts[0].tickets[0].selectedSpotIds,[s.first,s.second].sort((a,b)=>a-b));assert.deepEqual(requirements.affectedSpotIds,[s.first,s.second].sort((a,b)=>a-b));
 const before=await state(s),p=await preview(s,[s.first],input);assert.equal(p.code,200,JSON.stringify(p));assert.deepEqual(p.quote.releasedSpotIds,[s.second]);assert.deepEqual(p.quote.spotIds,[s.first]);assert.equal(p.quote.seats.find(x=>x.spotId===s.second).stateBefore,'ordered');assert.equal(p.quote.seats.find(x=>x.spotId===s.second).stateAfter,'available');assert.deepEqual(await state(s),before);
 const done=await apply(s,p,input);assert.equal(done.status,'applied',JSON.stringify(done));const after=await state(s);assert.equal(after.spots.find(x=>Number(x.id)===s.second).order_product_ticket,null);assert.notEqual(after.spots.find(x=>Number(x.id)===s.first).order_product_ticket,null);
});

test('missing required second-ticket answers identify the field and leave old tickets, money, history and delivery intact',options,async t=>{
 const s=await paidAtomicSwap(t);await bank(s);await s.db.query('RESET ROLE');const field=Number((await s.db.query("insert into form_fields(form,type,title,is_required,is_hidden,is_ticket_field) values($1,'text','Attendee',true,false,true) returning id",[s.fx.form])).rows[0].id);await s.db.query('SET LOCAL ROLE authenticated');
 const selected=s.source.map(b=>b.spotId),first=selected[0],second=selected[1],input={email:'required@example.invalid',form_key:s.fx.formKey,ticket_fields:{[first]:[{_subFieldId:field,text:'First attendee',[field]:'First attendee'}]}};
 const before=await state(s),bad=await preview(s,[first],input,false);assert.equal(bad.code,409);assert.equal(bad.reason,'REQUIRED_FIELD_MISSING');assert.equal(bad.fieldId,field);assert.deepEqual(await state(s),before,'later ticket validation failure rolls back earlier ticket allocation and old cancellation');
 input.ticket_fields[second]=[{_subFieldId:field,text:'Second attendee',[field]:'Second attendee'}];const p=await preview(s,[first],input);assert.equal(p.code,200,JSON.stringify(p));assert.equal((await apply(s,p,input)).status,'applied');
});

function invoiceClient(s){const signatures={get_external_services:['p_order_id'],get_fakturoid_ticket_order_state_v1:['p_order_id'],claim_replacement_invoice_preparation:['p_order','p_command'],mark_replacement_invoice_dispatch:['p_order','p_command','p_token'],release_replacement_invoice_preparation:['p_order','p_command','p_token','p_not_created'],complete_replacement_invoice_preparation:['p_order','p_command','p_token','p_variable_symbol'],complete_fakturoid_ticket_order_v1:['p_order_id','p_command_id','p_variable_symbol'],abort_fakturoid_ticket_order_v1:['p_order_id','p_command_id']};const calls=[];return{calls,rpc:async(name,args)=>{
 assert(Object.hasOwn(signatures,name),'known real SQL fulfillment owner');calls.push(name);await s.db.query('RESET ROLE');await s.db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','service_role',true)");await s.db.query('SAVEPOINT invoice_rpc');try{const keys=signatures[name],params=keys.map(k=>args[k]),placeholders=params.map((_,i)=>'$'+(i+1)).join(',');const sql=name==='get_external_services'?`select coalesce(jsonb_agg(to_jsonb(x)),'[]') value from get_external_services(${placeholders}) x`:`select ${name}(${placeholders}) value`;const data=(await s.db.query(sql,params)).rows[0].value;await s.db.query('RELEASE SAVEPOINT invoice_rpc');return{data,error:null};}catch(error){await s.db.query('ROLLBACK TO SAVEPOINT invoice_rpc');await s.db.query('RELEASE SAVEPOINT invoice_rpc');return{data:null,error};}finally{await s.db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');}
}};}
async function invoiceFixture(t,persistent=false){const s=await paidAtomicSwap(t,persistent);await bank(s);await s.db.query('RESET ROLE');await s.db.query("insert into eshop.external_services(unit,type,data) values($1,'FAKTUROID',$2)",[s.f.unit,{client_id:'local',client_secret:'local',slug:'local',subject_id:1}]);await s.db.query('SET LOCAL ROLE authenticated');const input={email:'invoice-replacement@example.invalid',form_key:s.fx.formKey},p=await preview(s,[s.first],input);assert.equal(p.code,200,JSON.stringify(p));assert.equal(p.quote.newOrder.state,'preparing_payment');const command=randomUUID(),done=await apply(s,p,input,command,true);assert.equal(done.status,'applied',JSON.stringify(done));return{...s,input,p,command,done,newOrder:Number(done.data.order.id)};}

test('real SQL and the actual fulfillment gateway preserve a committed replacement across unknown invoice POST, negative lookup and eventual recovery',options,async t=>{
 const {prepareFakturoidTicketOrder}=await import('../../../supabase/functions/send-ticket-order/fakturoidPreparation.ts');const {createFakturoidGateway}=await import('../../../supabase/functions/send-ticket-order/fakturoid.ts');
 const s=await invoiceFixture(t),client=invoiceClient(s);let posts=0,invoice,dispatched;
 const gateway=createFakturoidGateway(async(url,init={})=>{const path=new URL(url).pathname,method=init.method??'GET';if(path.endsWith('/oauth/token'))return Response.json({access_token:'local-token'});if(method==='GET')return Response.json(invoice?[invoice]:[]);if(method==='POST'){posts++;dispatched=JSON.parse(init.body);throw new TypeError('Synthetic invoice response lost; provider may still finish');}if(method==='PATCH'||method==='PUT')return Response.json(invoice);throw new Error('Unexpected provider stub route');});
 const args={client,gateway,order:structuredClone(s.done.data.order),commandId:s.command,unitName:'Local invoice fixture',replacement:true},before=await state(s);
 const first=await prepareFakturoidTicketOrder(args);assert.equal(first.ok,false);assert.equal(first.retrySameCommand,true);assert.equal(posts,1);assert.deepEqual(await state(s),before,'provider uncertainty cannot cancel the new allocation after old tickets were canceled');assert(!client.calls.includes('abort_fakturoid_ticket_order_v1'));
 const unknown=await prepareFakturoidTicketOrder(args);assert.equal(unknown.ok,false);assert.equal(posts,1,'a negative lookup never reopens uncertain invoice POST');assert.deepEqual(await state(s),before);
 invoice={id:555,variable_symbol:String(dispatched.variable_symbol)};const recovered=await prepareFakturoidTicketOrder(args);assert.equal(recovered.ok,true);assert.equal(posts,1);const after=await state(s);assert.equal(after.orders.find(o=>Number(o.id)===s.newOrder).state,'ordered');assert.equal(after.spots.filter(x=>x.order_product_ticket!==null).length,2);assert(!client.calls.includes('abort_fakturoid_ticket_order_v1'));
 assert.deepEqual(await apply(s,s.p,s.input,s.command,true),s.done,'core receipt remains original while fulfillment advances');
});

test('two real connections fence invoice dispatch and expired leases; API roles cannot forge the private preparation job',options,async t=>{
 const s=await invoiceFixture(t,true);await s.db.query('COMMIT');const one=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL),two=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 const worker=async(db,sql,args)=>{await db.query('BEGIN');try{await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','service_role',true)");const r=(await db.query(sql,args)).rows[0]?.v;await db.query('COMMIT');return r;}catch(e){await db.query('ROLLBACK');throw e;}};
 try{
  const first=await worker(one,'select claim_replacement_invoice_preparation($1,$2) v',[s.newOrder,s.command]);assert.equal(first.status,'claimed');assert.equal(first.allowCreate,true);
  const busy=await worker(two,'select claim_replacement_invoice_preparation($1,$2) v',[s.newOrder,s.command]);assert.equal(busy.status,'busy');assert.equal(busy.token,undefined);
  await assert.rejects(worker(two,'select mark_replacement_invoice_dispatch($1,$2,$3) v',[s.newOrder,s.command,randomUUID()]),e=>e.code==='23514');
  await worker(one,'select mark_replacement_invoice_dispatch($1,$2,$3) v',[s.newOrder,s.command,first.token]);
  await s.db.query("update eshop.replacement_invoice_preparations set lease_until=clock_timestamp()-interval '1 second' where command_id=$1 and order_id=$2",[s.command,s.newOrder]);
  const retry=await worker(two,'select claim_replacement_invoice_preparation($1,$2) v',[s.newOrder,s.command]);assert.equal(retry.status,'claimed');assert.equal(retry.allowCreate,false);assert.notEqual(retry.token,first.token);
  const symbol=(await s.db.query('select variable_symbol from eshop.payment_info where id=(select payment_info from eshop.orders where id=$1)',[s.newOrder])).rows[0].variable_symbol;
  await assert.rejects(worker(one,'select complete_replacement_invoice_preparation($1,$2,$3,$4) v',[s.newOrder,s.command,first.token,symbol]),e=>e.code==='23514');
  await assert.rejects(worker(two,'select mark_replacement_invoice_dispatch($1,$2,$3) v',[s.newOrder,s.command,retry.token]),e=>e.code==='23514','even a fresh worker cannot force a second uncertain POST');
  await worker(two,'select complete_replacement_invoice_preparation($1,$2,$3,$4) v',[s.newOrder,s.command,retry.token,symbol]);
  const job=(await s.db.query('select state,lease_token from eshop.replacement_invoice_preparations where command_id=$1',[s.command])).rows[0];assert.equal(job.state,'complete');assert.equal(job.lease_token,null);
  for(const signature of ['claim_replacement_invoice_preparation(bigint,uuid)','mark_replacement_invoice_dispatch(bigint,uuid,uuid)','release_replacement_invoice_preparation(bigint,uuid,uuid,boolean)','complete_replacement_invoice_preparation(bigint,uuid,uuid,bigint)'])for(const role of ['anon','authenticated'])assert.equal((await s.db.query("select has_function_privilege($1,to_regprocedure('public.'||$2),'EXECUTE') allowed",[role,signature])).rows[0].allowed,false);
  assert.equal((await s.db.query("select has_table_privilege('authenticated','eshop.replacement_invoice_preparations','INSERT,UPDATE,DELETE,SELECT') allowed")).rows[0].allowed,false);
 }finally{await one.end();await two.end();}
});

test('MCP requirements, approval and uncertain retry execute the actual Edge coordinator and one SQL intent without private customer payloads',options,async t=>{
 const {executeConfirmedSeatOrder}=await import('../../../supabase/functions/send-ticket-order/confirmedReplacement.ts');const {resolveTicketOrderCommandIdentity}=await import('../../../supabase/functions/send-ticket-order/commandIdentity.ts');
 const s=await paidAtomicSwap(t);await bank(s);let coreCalls=0,serviceCalls=0;
 const userClient={rpc:async(name,a)=>{assert.equal(name,'create_blueprint_seat_order');coreCalls++;await s.db.query('SAVEPOINT edge_core');try{const data=(await s.db.query('select create_blueprint_seat_order($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13) v',[a.p_occasion,a.p_organization,a.p_unit,a.p_blueprint,a.p_spots,a.p_input,a.p_target_spots,a.p_affected_spots,JSON.stringify(a.p_blueprints),a.p_confirmation_hash,a.p_command_id,a.p_editor,a.p_expected_actor])).rows[0].v;await s.db.query('RELEASE SAVEPOINT edge_core');return{data,error:null};}catch(error){await s.db.query('ROLLBACK TO SAVEPOINT edge_core');await s.db.query('RELEASE SAVEPOINT edge_core');return{data:null,error};}}};
 const ex=executor(s.db,s.f,{invokeEdge:async(name,{body})=>{assert.equal(name,'send-ticket-order');assert.equal(body.clientId,ex.owner.profile.binding,'existing authenticated session binding stays stable across retries');assert(resolveTicketOrderCommandIdentity(body.commandId,body.clientId,body.replacement));const data=await executeConfirmedSeatOrder({replacement:body.replacement,commandId:body.commandId,client:userClient,serviceClient:{rpc:()=>{serviceCalls++;throw new Error('No invoice metadata read is needed for an already-ordered bank receipt');}},gateway:{preparePayment:()=>{throw new Error('No provider on ordinary bank order');}}});return{data,error:null};}});
 const requirements=await ex.previewOrder([s.first]);assert.equal(requirements.ok,true,JSON.stringify(requirements));assert.equal(requirements.data.mode,'requirements');assert.equal(requirements.data.spotIds.length,2);assert.equal(requirements.data.conflicts[0].customer.email,'private-swap@example.invalid','orders-read explicitly permits the contacts required for cancellation approval');
 const input={email:'mcp-order@example.invalid',form_key:requirements.data.formKey},before=await state(s),p=await ex.previewOrder([s.first],input);assert.equal(p.ok,true,JSON.stringify(p));assert.equal(p.data.mode,'quote');assert.deepEqual(await state(s),before);
 const originalScope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:s.f.org,unitId:s.f.unit+99999});assert.equal((await ex.createOrder(p.data,input)).error.code,'FORBIDDEN');ex.owner.delegatedContext=originalScope;
 const command=randomUUID();ex.stats.lose=true;const uncertain=await ex.createOrder(p.data,input,command);assert.equal(uncertain.ok,false);assert.equal(uncertain.error.retryable,true);const after=await state(s);
 const resumed=await ex.createOrder(p.data,input,command);assert.equal(resumed.ok,true,JSON.stringify(resumed));assert.equal(resumed.data.status,'applied');assert.equal(resumed.data.fulfillmentStatus,'ready');assert.equal(resumed.data.retrySameCommand,false);assert(!JSON.stringify(resumed).includes(input.email));assert.equal(resumed.data.quote.newOrder.products,undefined);assert.equal(resumed.data.quote.seats,undefined);assert.deepEqual(await state(s),after);assert.equal(serviceCalls,0);
 assert.equal(coreCalls,3,'one denied attempt, one atomic intent, one receipt replay');t.diagnostic('Serialized domain responses: '+JSON.stringify(ex.stats.payloadBytes));
});

test('two connections: seat order waits for checkout and authorization revocation without partial financial effects',options,async t=>{
 const s=await setup(t,true);await bank(s);
 const {db,f,fx,bindings}=s,buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);
 const input={email:'concurrent-order@example.invalid',form_key:fx.formKey};let pending;
 const beginActor=async()=>{await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');};
 const waitBlocked=async()=>{for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) blocked',[buyer.processID,db.processID])).rows[0].blocked)return;await new Promise(r=>setTimeout(r,10));}assert.fail('order must wait on the actual concurrent aggregate lock');};
 try{
  const p=await preview(s,[bindings[0].spotId],input),before=await state(s);await db.query('COMMIT');
  const secret=randomUUID();await buyer.query('BEGIN');
  assert.equal((await buyer.query('select select_spot($1,$2,$3,true) v',[fx.formKey,secret,bindings[0].spotId])).rows[0].v.code,200);
  await beginActor();pending=apply(s,p,input).then(value=>({value}),error=>({error}));await waitBlocked();await buyer.query('COMMIT');
  const attempt=await pending;pending=null;assert.equal(attempt.error,undefined);assert.equal(attempt.value.status,'rejected',JSON.stringify(attempt));
  await db.query('COMMIT');const after=await state(s);
  for(const key of ['orders','payments','tickets','items','history','email'])assert.deepEqual(after[key],before[key],key+' unchanged');
  assert.equal(after.spots.find(row=>Number(row.id)===bindings[0].spotId).secret,secret);
  await db.query('COMMIT');
  assert.equal((await buyer.query('select select_spot($1,$2,$3,false) v',[fx.formKey,secret,bindings[0].spotId])).rows[0].v.code,200);
  await beginActor();const fresh=await preview(s,[bindings[0].spotId],input);assert.equal(fresh.code,200);await db.query('COMMIT');
  await buyer.query('BEGIN');await buyer.query('select lock_blueprint_scope_internal($1)',[[f.occasion]]);
  await beginActor();const command=randomUUID();pending=apply(s,fresh,input,command).then(value=>({value}),error=>({error}));await waitBlocked();
  await buyer.query('update occasion_users set is_editor=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await buyer.query('COMMIT');
  const revoked=await pending;pending=null;assert.equal(revoked.error?.code,'42501');await db.query('ROLLBACK');
  assert.equal(Number((await buyer.query('select count(*) n from client_mutation_receipts where command_id=$1',[command])).rows[0].n),0);
  const final=await state(s);for(const key of ['orders','payments','tickets','items','history','email'])assert.deepEqual(final[key],before[key],key+' unchanged after permission revocation');
 }finally{await buyer.query('ROLLBACK');await buyer.end();if(pending)await pending;}
});

test('released replacement adapter keeps its original input fingerprint and replays without another allocation or notice',options,async t=>{
 const s=await setup(t);await bank(s);
 const input={email:'legacy-replacement@example.invalid',form_key:s.fx.formKey},ids=s.bindings.slice(0,2).map(x=>x.spotId).sort((a,b)=>a-b),command=randomUUID();
 const call=async()=>(await s.db.query('select replace_blueprint_order_client_sync_v1($1,$2,$3) v',[ids,input,command])).rows[0].v;
 const done=await call();assert.equal(done.status,'applied',JSON.stringify(done));assert.equal(done.data.quote,undefined,'released shape does not require the new confirmation contract');
 const before=await state(s);assert.deepEqual(await call(),done);assert.deepEqual(await state(s),before);
 await s.db.query('RESET ROLE');
 const stored=(await s.db.query('select request_sha256 from client_mutation_receipts where command_id=$1',[command])).rows[0];
 const original=(await s.db.query("select encode(extensions.digest(convert_to(jsonb_build_object('spots',$1::bigint[],'input',$2::jsonb)::text,'UTF8'),'sha256'),'hex') hash",[ids,input])).rows[0].hash;
 assert.equal(stored.request_sha256,original,'the released 3-argument fingerprint stays unchanged');
});
