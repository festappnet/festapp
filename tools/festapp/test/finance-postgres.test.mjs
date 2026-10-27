import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';
import {agendaDescriptors} from '../src/operations/agenda.mjs';
import {lifecycleDescriptors} from '../src/operations/lifecycle.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {setup} from './finance-fixtures.mjs';
import {denied} from './form-fixtures.mjs';
import {financeDescriptors,invokeFinanceOperation} from '../src/operations/finance.mjs';
const account={accountId:null,accountNumber:'CZ6508000000192000145399',title:'Bank fixture',creditorName:'Test',type:'FIO',currencies:['CZK'],displayNumber:'19-2000145399/0800'};
test('bank creation, details, role changes and links share receipts; provider details intent is not duplicated',async t=>{
 const s=await setup(t),command=randomUUID();const created=await s.bank('save',account,command);assert.equal(created.code,200,JSON.stringify(created));const id=created.data.accountId;
 assert.deepEqual(await s.bank('save',account,command),created);assert.equal((await s.bank('list')).items.filter(x=>x.id===id).length,1);
 const changed={...account,accountId:id,title:'Renamed'};const update=randomUUID();await s.db.query('RESET ROLE');
 await s.db.query("insert into eshop.bank_sync_connections(bank_account_id,instance_id,remote_bank_account_id,mode,state,manifest_sha256,legacy_blocked_at,consumer_app_id,physical_account,provider) values($1,'fixture','12','api','connected',repeat('a',64),now(),'festapp','fixture-account','FIO')",[id]);await s.db.query('SET LOCAL ROLE authenticated');
 const saved=await s.bank('save',changed,update);assert(saved.data.detailsSyncPending);assert.deepEqual(await s.bank('save',changed,update),saved);
 await s.db.query('RESET ROLE');assert.equal(Number((await s.db.query("select count(*) n from eshop.bank_sync_operations where bank_account_id=$1 and operation='update_details'",[id])).rows[0].n),1);await s.db.query('SET LOCAL ROLE authenticated');
 const unlink=randomUUID();await s.bank('link',{accountId:id,priority:null,force:false},unlink);await s.bank('link',{accountId:id,priority:null,force:false},unlink);
 assert(!(await s.bank('list')).items.some(x=>x.id===id));
});
test('bank admin AND actual linked non-demo manager remain required, including on receipt replay',async t=>{
 const s=await setup(t),command=randomUUID();const created=await s.bank('save',account,command),id=created.data.accountId;
 await s.db.query('RESET ROLE');await s.db.query('update eshop.bank_account_users set is_admin=false where bank_account=$1 and "user"=$2',[id,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 await denied(s.db,"select manage_bank_authoring($1,$2,'status',$3)",[s.f.unit,s.f.org,{accountId:id}]);
 await denied(s.db,"select manage_bank_authoring($1,$2,'save',$3,$4)",[s.f.unit,s.f.org,{...account,accountId:id},randomUUID()]);
 await s.db.query('RESET ROLE');
 const second=Number((await s.db.query("insert into units(title,organization) values('Other linked organizer',$1) returning id",[s.f.org])).rows[0].id);
 await s.db.query('insert into unit_users(unit,"user",is_manager) values($1,$2,true)',[second,s.f.actor]);await s.db.query('insert into eshop.unit_bank_accounts(unit,bank_account,priority) values($1,$2,0)',[second,id]);await s.db.query('SET LOCAL ROLE authenticated');
 await s.db.query('RESET ROLE');await s.db.query('update eshop.bank_account_users set is_admin=true where bank_account=$1 and "user"=$2',[id,s.f.actor]);await s.db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[s.f.unit,s.f.actor]);await s.db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,true)',[s.f.org,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 assert.equal((await s.db.query('select can_manage_bank_account($1) allowed',[id])).rows[0].allowed,true,'ordinary bank right via another linked organizer must not widen this selected organizer consent');
 await denied(s.db,"select manage_bank_authoring($1,$2,'save',$3,$4)",[s.f.unit,s.f.org,account,command]);
 await denied(s.db,"select manage_bank_authoring($1,$2,'status',$3)",[s.f.unit,s.f.org,{accountId:id}]);
});
test('ordinary executor uses scoped bank boundary and rejects credential/schema injection',async t=>{
 const s=await setup(t);const owner={...s.owner,delegatedUnitContext:async(_client,unitId)=>{assert.equal(unitId,s.f.unit);return{organizationId:s.f.org,unitId};}};
 const op=financeDescriptors.find(x=>x.id==='banks.save');assert(!op.input.safeParse({...account,unitId:s.f.unit,commandId:randomUUID(),token:'secret'}).success);
 const input=op.input.parse({...account,unitId:s.f.unit,commandId:randomUUID()});const created=await invokeFinanceOperation(owner,s.client,op.id,input);assert(created.data.accountId);
 const listed=await invokeFinanceOperation(owner,s.client,'banks.list',{unitId:s.f.unit,limit:10});assert(listed.items.some(x=>x.id===created.data.accountId));assert(!JSON.stringify(listed).includes('pairing'));
});

test('real card-provider fixtures preserve observed refunds and completed disconnect recovery',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');
 for(const name of ['helpers/assertions.sql','scanning/fixture.sql'])await s.db.query(await readFile(new URL('../../../database/tests/'+name,import.meta.url),'utf8'));
 for(const name of ['connections.sql','connection_status.sql','refund_decisions.sql','admin_detail.sql'])await s.db.query(await readFile(new URL('../../../database/functions/eshop_stripe/'+name,import.meta.url),'utf8'));
 let disconnect=await readFile(new URL('../../../database/tests/eshop/stripe/disconnect_test.sql',import.meta.url),'utf8');
 disconnect=disconnect.replace('END $$;',()=>" PERFORM assert_eq(public.begin_stripe_disconnect(unit_id,false,connection),intent,'completed exact retry retains its original provider intent');\nEND $$;");
 await s.db.query(disconnect);await s.db.query('RESET ROLE');
 let refund=await readFile(new URL('../../../database/tests/eshop/stripe/refund_decisions_test.sql',import.meta.url),'utf8');
 refund=refund.replace("result:=public.decide_stripe_partial_refund_client_sync_v1(oid,'keep','{}','Price adjustment without cancellation',2345,command)","result:=public.manage_card_refund_authoring(oc,org,u,oid,jsonb_build_object('action','keep','ticketIds','[]'::jsonb,'note','Price adjustment without cancellation','expectedRefundedMinor',2345),command)");
 await s.db.query(refund);
});

test('card pause and disconnection commands freeze identity instead of reapplying an old desired state',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');
 const connection=(await s.db.query("insert into eshop.stripe_connections(organization_id,unit_id,account_id,livemode,state,paused) values($1,$2,'acct_scopedReceiptFixture',false,'connected',false) returning id",[s.f.org,s.f.unit])).rows[0].id;await s.db.query('SET LOCAL ROLE authenticated');
 const id=randomUUID();const first=(await s.db.query('select set_stripe_unit_paused_client_sync_v1($1,false,true,$2) value',[s.f.unit,id])).rows[0].value;
 await s.db.query('select set_stripe_unit_paused_client_sync_v1($1,false,false,$2)',[s.f.unit,randomUUID()]);
 assert.deepEqual((await s.db.query('select set_stripe_unit_paused_client_sync_v1($1,false,true,$2) value',[s.f.unit,id])).rows[0].value,first);
 assert.equal((await s.db.query('select get_stripe_unit_connection($1,false) value',[s.f.unit])).rows[0].value.paused,false);
 const disconnect=randomUUID();const accepted=(await s.db.query('select begin_stripe_disconnect_client_sync_v1($1,false,$2,$3) value',[s.f.unit,connection,disconnect])).rows[0].value;
 assert.deepEqual((await s.db.query('select begin_stripe_disconnect_client_sync_v1($1,false,$2,$3) value',[s.f.unit,connection,disconnect])).rows[0].value,accepted);
 await denied(s.db,'select begin_stripe_disconnect_client_sync_v1($1,false,$2,$3)',[s.f.unit,randomUUID(),disconnect],'22023');
 await s.db.query('RESET ROLE');await s.db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[s.f.unit,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 await denied(s.db,'select begin_stripe_disconnect_client_sync_v1($1,false,$2,$3)',[s.f.unit,connection,disconnect]);
});
test('standalone account UI resolves an actually manageable linked organizer and retains it on replay',async t=>{
 const s=await setup(t);const created=await s.bank('save',account,randomUUID());
 const id=randomUUID(),payload={...account,accountId:created.data.accountId,title:'Standalone UI'};
 const first=(await s.db.query('select manage_bank_authoring(null,null,\'save\',$1,$2) value',[payload,id])).rows[0].value;assert.equal(first.code,200);
 assert.deepEqual((await s.db.query('select manage_bank_authoring(null,null,\'save\',$1,$2) value',[payload,id])).rows[0].value,first);
});


test('actual SDK discovers and executes the new bank, organizer-agenda and lifecycle boundaries',async t=>{
 const s=await setup(t);const owner={...s.owner,allowedOperations:[...financeDescriptors,...agendaDescriptors,...lifecycleDescriptors].map(d=>d.id),delegatedUnitContext:async(_client,unitId)=>{assert.equal(unitId,s.f.unit);return{organizationId:s.f.org,unitId};}};
 const server=createServer(new Operations(owner)),client=new Client({name:'final-domain-fixture',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(b);await client.connect(a);t.after(async()=>{await client.close();await server.close();});
 const names=(await client.listTools()).tools.map(t=>t.name);for(const name of ['festapp_banks_save','festapp_units_quotes_save','festapp_occasions_copy'])assert(names.includes(name));
 const bank=await client.callTool({name:'festapp_banks_save',arguments:{...account,unitId:s.f.unit,commandId:randomUUID()}});assert.equal(bank.structuredContent.ok,true,JSON.stringify(bank));
 const copy=await client.callTool({name:'festapp_occasions_copy',arguments:{occasionId:s.f.occasion,targetUnitId:s.f.unit,locale:'en',commandId:randomUUID()}});assert.equal(copy.structuredContent.ok,true,JSON.stringify(copy));assert.equal(copy.structuredContent.data.state,'complete');
});
