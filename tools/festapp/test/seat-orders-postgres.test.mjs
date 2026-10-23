import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setup,paidAtomicSwap} from './seat-fixtures.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
async function bank(s){await s.db.query('RESET ROLE');const id=Number((await s.db.query("insert into eshop.bank_accounts(title,type,supported_currencies,account_number,account_number_human_readable) values('Local order fixture','FIO',array['CZK'],'CZ6508000000192000145399','19-2000145399/0800') returning id")).rows[0].id);await s.db.query('insert into eshop.unit_bank_accounts(unit,bank_account) values($1,$2)',[s.f.unit,id]);await s.db.query('SET LOCAL ROLE authenticated');}
async function preview(s,ids,input=null,diagnose=true){const f=s.f;const value=(await s.db.query('select preview_blueprint_seat_order($1,$2,$3,$4,$5,$6) v',[f.occasion,f.org,f.unit,f.blueprint,ids,input])).rows[0].v;
 if(input&&value.code!==200&&diagnose){await s.db.query('RESET ROLE');await s.db.query('SAVEPOINT explain_quote');try{await s.db.query('select blueprint_seat_order_quote_internal(apply_blueprint_seat_order_internal(blueprint_seat_order_selection_internal($1,$2,$3,1000),$4,$5))',[f.occasion,f.blueprint,ids,input,randomUUID()]);}catch(e){throw new Error('Actual quote owner: '+e.message+'; '+(e.detail??'')+'; '+(e.where??''));}finally{await s.db.query('ROLLBACK TO SAVEPOINT explain_quote');await s.db.query('RELEASE SAVEPOINT explain_quote');await s.db.query('SET LOCAL ROLE authenticated');}}
 return value;}
async function apply(s,p,input,command=randomUUID()){const f=s.f;return(await s.db.query('select create_blueprint_seat_order($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) v',[f.occasion,f.org,f.unit,f.blueprint,p.requestedSpotIds,input,p.quote.spotIds,p.quote.affectedSpotIds,JSON.stringify(p.quote.blueprints),p.confirmationHash,command])).rows[0].v;}
async function state(s){await s.db.query('RESET ROLE');const r=(await s.db.query(`select jsonb_build_object(
 'orders',(select coalesce(jsonb_agg(to_jsonb(o) order by id),'[]') from eshop.orders o where occasion=$1),
 'payments',(select coalesce(jsonb_agg(to_jsonb(p) order by p.id),'[]') from eshop.payment_info p where id in(select payment_info from eshop.orders where occasion=$1)),
 'tickets',(select coalesce(jsonb_agg(to_jsonb(t) order by id),'[]') from eshop.tickets t where occasion=$1),
 'items',(select coalesce(jsonb_agg(to_jsonb(i) order by id),'[]') from eshop.order_product_ticket i where "order" in(select id from eshop.orders where occasion=$1)),
 'spots',(select coalesce(jsonb_agg(to_jsonb(s) order by id),'[]') from eshop.spots s where occasion=$1),
 'history',(select coalesce(jsonb_agg(to_jsonb(h) order by id),'[]') from eshop.orders_history h where "order" in(select id from eshop.orders where occasion=$1)),
 'email',(select coalesce(jsonb_agg(to_jsonb(e) order by id),'[]') from email_messages e where occasion=$1)) v`,[s.f.occasion])).rows[0].v;await s.db.query('SET LOCAL ROLE authenticated');return r;}

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
 const input={email:'new-owner@example.invalid',form_key:s.fx.formKey},requirements=await preview(s,[s.first]);assert.equal(requirements.conflicts.length,1);const both=await preview(s,[s.first,s.second]);assert.equal(both.conflicts.length,1,'one original ticket is never duplicated by its two seat bindings');assert.deepEqual(both.conflicts[0].selectedSpotIds,[s.first,s.second].sort((a,b)=>a-b));assert.deepEqual(requirements.affectedSpotIds,[s.first,s.second].sort((a,b)=>a-b));
 const before=await state(s),p=await preview(s,[s.first],input);assert.equal(p.code,200,JSON.stringify(p));assert.deepEqual(p.quote.releasedSpotIds,[s.second]);assert.deepEqual(p.quote.spotIds,[s.first]);assert.equal(p.quote.seats.find(x=>x.spotId===s.second).stateBefore,'ordered');assert.equal(p.quote.seats.find(x=>x.spotId===s.second).stateAfter,'available');assert.deepEqual(await state(s),before);
 const done=await apply(s,p,input);assert.equal(done.status,'applied',JSON.stringify(done));const after=await state(s);assert.equal(after.spots.find(x=>Number(x.id)===s.second).order_product_ticket,null);assert.notEqual(after.spots.find(x=>Number(x.id)===s.first).order_product_ticket,null);
});

test('missing required second-ticket answers identify the field and leave old tickets, money, history and delivery intact',options,async t=>{
 const s=await paidAtomicSwap(t);await bank(s);await s.db.query('RESET ROLE');const field=Number((await s.db.query("insert into form_fields(form,type,title,is_required,is_hidden,is_ticket_field) values($1,'text','Attendee',true,false,true) returning id",[s.fx.form])).rows[0].id);await s.db.query('SET LOCAL ROLE authenticated');
 const selected=s.source.map(b=>b.spotId),first=selected[0],second=selected[1],input={email:'required@example.invalid',form_key:s.fx.formKey,ticket_fields:{[first]:[{_subFieldId:field,text:'First attendee',[field]:'First attendee'}]}};
 const before=await state(s),bad=await preview(s,[first],input,false);assert.equal(bad.code,409);assert.equal(bad.reason,'REQUIRED_FIELD_MISSING');assert.equal(bad.fieldId,field);assert.deepEqual(await state(s),before,'later ticket validation failure rolls back earlier ticket allocation and old cancellation');
 input.ticket_fields[second]=[{_subFieldId:field,text:'Second attendee',[field]:'Second attendee'}];const p=await preview(s,[first],input);assert.equal(p.code,200,JSON.stringify(p));assert.equal((await apply(s,p,input)).status,'applied');
});
