import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {postgresApi} from './api-postgres-fixture.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};

function event(title='Program item') {return{title,startTime:new Date(Date.now()+3600000).toISOString(),endTime:new Date(Date.now()+7200000).toISOString(),maxParticipants:10,description:'Scoped program',placeId:null,splitForMenWomen:false,isGroupEvent:false,isHidden:false,type:null,data:{is_cancelled:false},order:0,parentEventIds:[],eventRoleIds:[]};}
const createEvent=s=>s.command('events.save',{expectedVersion:null,entity:event()});
const read=(s,domain,id)=>s.invoke(domain+'.inspect',{entityId:id});

test('HTTP SQL: schedule event and exclusive-group commands preserve full relationships, original version and frozen replay',options,async t=>{
 const s=await postgresApi(t);const created=await createEvent(s);assert(created.entityId);
 const state=await read(s,'events',created.entityId);assert.equal(state.aggregateVersion,created.aggregateVersion);assert.equal(state.entity.title,'Program item');
 const request={entity:{...event('Confirmed edit'),id:created.entityId},expectedVersion:state.aggregateVersion,commandId:randomUUID()};const edited=await s.invoke('events.save',request);assert.deepEqual(await s.invoke('events.save',request),edited);
 await assert.rejects(s.command('events.save',{...request,commandId:randomUUID()}),e=>e.code==='PROGRAM_CHANGED_RELOAD_REQUIRED');
 const group=await s.command('exclusiveGroups.save',{expectedVersion:null,entity:{title:'Choose one',events:[created.entityId]}});assert(group.entityId);
 const g=await read(s,'exclusiveGroups',group.entityId);assert.equal(g.entity.exclusive_events[0].event,created.entityId);
 assert.equal((await s.command('exclusiveGroups.delete',{entityId:group.entityId,expectedVersion:g.aggregateVersion})).status,'applied');
 const current=await read(s,'events',created.entityId);assert.equal((await s.command('events.delete',{entityId:created.entityId,expectedVersion:current.aggregateVersion})).status,'applied');
});
test('HTTP SQL: map place/type/path and move delegate to their versioned owners without exposing an editor bundle',options,async t=>{
 const s=await postgresApi(t);const place=await s.command('places.save',{expectedVersion:null,entity:{title:'Meeting point',description:'Here',type:null,coordinates:{latLng:{lat:50,lng:14}},isHidden:false,order:0,icon:null}});assert(place.entityId);
 const moved=await s.command('places.move',{entityId:place.entityId,expectedVersion:place.aggregateVersion,lat:51,lng:15});const p=await read(s,'places',place.entityId);assert.equal(p.aggregateVersion,moved.aggregateVersion);
 const type=await s.command('placeTypes.save',{expectedVersion:null,entity:{code:'rest',title:'Rest',icon:null,order:0,isHidden:false,isDefault:false}});assert(type.entityId);
 const path=await s.command('paths.save',{expectedVersion:null,entity:{title:'Walk',pathData:[[place.entityId,{lat:51.1,lng:15.1}]],data:{},icon:null,isHidden:false,order:0}});assert(path.entityId);
 const listed=await s.invoke('paths.list',{limit:1});assert.equal(listed.items.length,1);assert(!JSON.stringify(listed).includes('path_data'));
 for(const [domain,result] of [['paths',path],['placeTypes',type],['places',moved]])assert.equal((await s.command(domain+'.delete',{entityId:result.entityId,expectedVersion:result.aggregateVersion})).status,'applied');
});
test('HTTP SQL: speaker topics, event assignments and counseling slots reuse existing scoped commands',options,async t=>{
 const s=await postgresApi(t);const e=await createEvent(s);
 const topic=await s.command('topics.save',{expectedVersion:null,entity:{title:'Topic',order:0,is_hidden:false}});assert(topic.entityId);
 const speaker=await s.command('speakers.save',{expectedVersion:null,entity:{title:'Speaker',subtitle:null,description:'Description',image:null,order:0,is_hidden:false,data:{},topics:[topic.entityId]}});assert(speaker.entityId);
 const inspected=await read(s,'speakers',speaker.entityId);assert.deepEqual(inspected.entity.topics,[topic.entityId]);
 const links=await s.invoke('eventSpeakers.inspect',{entityId:e.entityId});await s.command('eventSpeakers.save',{entityId:e.entityId,expectedVersion:links.aggregateVersion,speakerIds:[speaker.entityId]});assert.deepEqual((await s.invoke('eventSpeakers.inspect',{entityId:e.entityId})).speakerIds,[speaker.entityId]);
 const slots=await s.command('counseling.createSlots',{entityId:speaker.entityId,start:new Date(Date.now()+10800000).toISOString(),end:new Date(Date.now()+14400000).toISOString(),slotMinutes:30,placeId:null,capacity:1,title:'Counseling',breakMinutes:0});assert(slots.eventIds.length>0,JSON.stringify(slots));
 assert((await s.invoke('counseling.list',{entityId:speaker.entityId,limit:50})).items.length>=slots.eventIds.length);
 const first=await read(s,'events',slots.eventIds[0]);await s.command('counseling.deleteSlot',{entityId:speaker.entityId,eventId:slots.eventIds[0],expectedVersion:first.aggregateVersion});
 await s.command('counseling.deleteEmptySlots',{entityId:speaker.entityId,from:null});
});
test('HTTP SQL: activities draft, discard and publish share canonical UTC history and never expose unrelated contacts',options,async t=>{
 const s=await postgresApi(t);const initial=await s.invoke('activities.inspect');assert.equal(initial.aggregateVersion,0);
 const graph=[{id:randomUUID(),title:'Help desk',description:null,type:null,unit:s.f.unit,is_hidden:false,order:0,data:{},assignments:[{id:randomUUID(),user:s.f.actor,start_time:new Date(Date.now()+10000).toISOString(),end_time:new Date(Date.now()+3600000).toISOString(),title:null,description:null,data:{},linked_place_ids:[],linked_event_ids:[]}]}];
 const saved=await s.command('activities.saveDraft',{expectedVersion:0,parentHistoryId:null,graph});assert(saved.draftId);
 const draft=await s.invoke('activities.inspect');assert.equal(draft.graph.length,0);assert.equal(draft.draftGraph.length,1);assert(!JSON.stringify(draft).includes('@example.invalid'));
 await s.command('activities.discardDraft',{expectedDraftId:saved.draftId});assert.equal((await s.invoke('activities.inspect')).draftId,null);
 const request={expectedVersion:0,parentHistoryId:null,graph,commandId:randomUUID()};const published=await s.invoke('activities.publish',request);assert.equal(published.aggregateVersion,1);assert.deepEqual(await s.invoke('activities.publish',request),published);assert.equal((await s.invoke('activities.inspect')).graph.length,1);
});
test('HTTP SQL: service definition edits are independent of participant assignments and exact replay survives later edits',options,async t=>{
 const s=await postgresApi(t);const args={type:'food',code:'lunch',title:'Lunch',reference:null,commandId:randomUUID()};const created=await s.invoke('services.create',args);assert.equal(created.status,'applied');
 await s.command('services.update',{type:'food',code:'lunch',title:'Later lunch',reference:null});assert.deepEqual(await s.invoke('services.create',args),created);
 const list=await s.invoke('services.list',{type:'food',limit:50});assert.equal(list.items.find(x=>x.code==='lunch').title,'Later lunch');
 await s.command('services.delete',{type:'food',code:'lunch',force:false});assert.equal((await s.invoke('services.list',{type:'food',limit:50})).items.length,0);
});

test('HTTP SQL: organizer and occasion settings, public link, profiles and groups share canonical versions and replay',options,async t=>{
 const s=await postgresApi(t),{f}=s;
 const unit=await s.invoke('units.settings.inspect',{unitId:f.unit});
 const settings={unitId:f.unit,commandId:randomUUID(),expectedVersion:unit.aggregateVersion,changes:{title:'API organizer'}};
 const changed=await s.invoke('units.settings.save',settings);
 assert.equal(changed.title,'API organizer');assert.deepEqual(await s.invoke('units.settings.save',settings),changed);
 const occasion=await s.invoke('occasions.settings.inspect');
 const saved=await s.command('occasions.settings.save',{expectedVersion:occasion.aggregateVersion,changes:{description:'Shared SQL owner'}});
 assert.equal(saved.description,'Shared SQL owner');
 const person=await s.command('profiles.create',{profile:{email:'http-'+randomUUID()+'@example.invalid',name:'Participant',note:'Original'}});
 const p=person.profile??person;
 const group={title:'Team',description:'Participants',type:null,placeId:null,participants:[{user_id:p.userId,is_admin:false}]};
 const request={commandId:randomUUID(),expectedVersion:null,group};
 const created=await s.invoke('groups.save',request);assert(created.groupId);
 assert.deepEqual(await s.invoke('groups.save',request),created);
 await s.command('groups.addMembers',{groupId:created.groupId,userIds:[f.actor]});
 const state=await s.invoke('groups.inspect',{groupId:created.groupId});
 assert.equal(state.participants.length,2);
 const profile=await s.invoke('profiles.inspect',{userId:p.userId});
 await s.command('profiles.save',{userId:p.userId,expectedVersion:profile.aggregateVersion,changes:{name:'Updated participant'}});
 assert.equal((await s.invoke('profiles.inspect',{userId:p.userId})).name,'Updated participant');
});

test('HTTP SQL: bank writes require DPoP/PAR and fresh MFA while SQL retains its two-role rule',options,async t=>{
 const s=await postgresApi(t,{strong:true}),{f,db}=s;
 const account={unitId:f.unit,accountId:null,accountNumber:'CZ6508000000192000145399',title:'Bank fixture',creditorName:'Test',type:'FIO',currencies:['CZK'],displayNumber:'19-2000145399/0800',commandId:randomUUID()};
 const created=await s.invoke('banks.save',account),id=created.data.accountId;assert(id);
 assert.deepEqual(await s.invoke('banks.save',account),created);
 assert.equal((await s.invoke('banks.list',{unitId:f.unit})).items.filter(x=>x.id===id).length,1);
 await db.query('RESET ROLE');await db.query('update eshop.bank_account_users set is_admin=false where bank_account=$1 and "user"=$2',[id,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const denied=await s.call('banks.save',{...account,accountId:id});assert.equal(denied.status,403);
 assert.equal((await denied.json()).outcome,'unknown'); // SQL was admitted and refused the current role.
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*)::int n from eshop.bank_accounts where id=$1',[id])).rows[0].n,1);
});

test('HTTP SQL: form CRUD and public link retain original versions and command identity',options,async t=>{
 const s=await postgresApi(t),{f}=s;
 const first=await s.command('forms.create',{title:'HTTP registration'}),formId=first.formId;
 assert(formId);const state=first.authoring;
 const request={commandId:randomUUID(),form:{id:formId,expected_aggregate_version:state.form.aggregate_version,
  expected_product_versions:state.productVersions,expected_product_type_versions:state.productTypeVersions,title:'Updated registration'}};
 const updated=await s.invoke('forms.save',request);assert.equal(updated.authoring.form.title,'Updated registration');
 assert.deepEqual(await s.invoke('forms.save',request),updated);
 const duplicate=await s.command('forms.duplicate',{sourceOccasionId:f.occasion,sourceFormId:formId,locale:'en'});
 assert.notEqual(duplicate.formId,formId);
 await s.command('forms.delete',{formId:duplicate.formId,expectedVersion:duplicate.authoring.form.aggregate_version});
 const link=await s.invoke('occasions.publicLink');
 const relinked=await s.command('occasions.setPublicLink',{expectedVersion:link.aggregateVersion,link:'http-'+randomUUID().slice(0,8)});assert.notEqual(relinked.link,link.link);
});

test('HTTP SQL: lost artwork response remains recoverable after OAuth reconnect with the original SQL command',options,async t=>{
 const s=await postgresApi(t);
 const current=await s.invoke('ticket_layouts.inspect');
 const {request}=await import('./layout-fixture.mjs');
 const {canonicalPreview}=await import('./render-fixture.mjs');
 const rendered=await canonicalPreview();
 const input=request(s.service.config.profile,{occasionId:s.f.occasion,expectedVersion:current.aggregate_version,
  expectedLayout:current.appearance.layout??null,nextLayout:{schemaVersion:3,templates:{named:rendered.resolve.template}}});
 s.loseNext();const lost=await s.call('ticket_layouts.save',input);assert.equal(lost.status,503,await lost.clone().text());
 assert.deepEqual(s.rpcFailures,[]);
 const pending=await s.invoke('ticket_layouts.pending');assert(pending.intent?.commandId);
 const command=pending.intent.commandId;
 await s.reconnect();
 const recovered=await s.invoke('ticket_layouts.pending');assert.equal(recovered.intent.commandId,command);
 const saved=await s.invoke('ticket_layouts.resume',{commandId:command});assert.equal(saved.commandId,command);assert.equal(saved.version,current.aggregate_version+1);
 assert.equal((await s.invoke('ticket_layouts.pending')).intent,null);
 const calls=s.rpcCalls.filter(c=>c.name==='save_delegated_ticket_layout');assert.equal(calls.length,2);
 assert.deepEqual(calls[0].args,calls[1].args);
});

test('HTTP SQL: inventory commands retain one receipt and narrow projections after a lost reply',options,async t=>{
 const s=await postgresApi(t),{f,db}=s;
 const request={commandId:randomUUID(),command:{action:'save_pool',expectedVersion:null,bundle:{pool:{occasion:f.occasion,title:'Inventory',description:null,type:null,sellable_capacity:null,data:{is_auto_resource_assignment:true}},contexts:[{title:'Day',block_date:null,order:1,data:null}]}}};
 s.loseNext();const lost=await s.call('inventory.change',request);assert.equal(lost.status,503);
 const saved=await s.invoke('inventory.change',request);assert.equal(saved.version,1);assert.equal(saved.pool.contexts.length,1);
 assert.deepEqual(await s.invoke('inventory.change',request),saved);
 const id=saved.pool.pool.id;
 const resource=await s.command('inventory.change',{command:{action:'save_resource',expectedVersion:null,resource:{inventory_pool:id,title:'Supply',capacity:4,booking_rules:{}}}});
 assert.equal(resource.resource.aggregate_version,1);
 const state=await s.invoke('inventory.pools.inspect',{poolId:id});assert.equal(state.settings.pool.title,'Inventory');
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*)::int n from inventory_pools where occasion=$1',[f.occasion])).rows[0].n,1);
});

test('HTTP SQL: email-template preview revision fences the shared mutation and replay',options,async t=>{
 const code='TICKET_ORDER_CONFIRMATION';
 const s=await postgresApi(t,{seed:(db,f)=>db.query("insert into email_templates(code,subject,html,title,organization) values($1,'Org subject','<p>Org body {{name}}</p>','Org template',$2)",[code,f.org])});
 const scope={entityType:'occasion',entityId:s.f.occasion};
 const state=await s.invoke('email_templates.inspect',{...scope,code,occasionId:undefined});
 const request={...scope,occasionId:undefined,code,expectedRevision:state.templates[0].revision,commandId:randomUUID(),command:{action:'save',title:'Saved',subject:'HTTP subject',html:'<p>Approved</p>'}};
 const changed=await s.invoke('email_templates.change',request);assert.equal(changed.templates[0].subject,'HTTP subject');
 assert.deepEqual(await s.invoke('email_templates.change',request),changed);
});

test('HTTP SQL: insufficient login strength challenges before any bank RPC is admitted',options,async t=>{
 const s=await postgresApi(t);
 const before=s.rpcCalls.length;
 const response=await s.call('banks.save',{unitId:s.f.unit,commandId:randomUUID(),accountId:null,accountNumber:'CZ6508000000192000145399',title:'Rejected',type:'FIO',currencies:['CZK'],displayNumber:null,creditorName:null});
 assert.equal(response.status,401);assert.match(response.headers.get('www-authenticate'),/insufficient_user_authentication/);
 assert.match(response.headers.get('www-authenticate'),/acr_values="urn:festapp:aal2"/);
 assert.equal((await response.json()).outcome,'rejected');assert.equal(s.rpcCalls.length,before);
});

test('HTTP SQL: orders and manual payment retain revision, ledger, mail intent and original replay across reconnect',options,async t=>{
 let orderId,secondOrder,productId,productType,fieldId,paymentId;
 const s=await postgresApi(t,{strong:true,seed:async(db,f)=>{
  const form=Number((await db.query("insert into forms(occasion,title,link,key,data) values($1,'Order HTTP form',gen_random_uuid()::text,gen_random_uuid(),'{}') returning id",[f.occasion])).rows[0].id);
  fieldId=Number((await db.query("insert into form_fields(form,title,type) values($1,'Email','email') returning id",[form])).rows[0].id);
  const bank=Number((await db.query("insert into eshop.bank_accounts(title,type,supported_currencies) values('HTTP bank','FIO',ARRAY['CZK']) returning id")).rows[0].id);
  await db.query('insert into eshop.unit_bank_accounts(unit,bank_account) values($1,$2)',[f.unit,bank]);
  productType=Number((await db.query("insert into eshop.product_types(occasion,title,type) values($1,'Admission','entry') returning id",[f.occasion])).rows[0].id);
  productId=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code,maximum) values($1,$2,'Admission',100,'CZK',100) returning id",[f.occasion,productType])).rows[0].id);
  for(let i=0;i<2;i++){
   const pi=Number((await db.query("insert into eshop.payment_info(amount,paid,returned,currency_code,variable_symbol,payment_method,bank_account) values(100,0,0,'CZK',12345,'bank',$1) returning id",[bank])).rows[0].id);
   const id=Number((await db.query("insert into eshop.orders(occasion,form,payment_info,state,price,currency_code,order_sequence,order_symbol,data) values($1,$2,$3,'ordered',100,'CZK',next_order_sequence($1),generate_order_symbol(),$4) returning id",[f.occasion,form,pi,{email:'buyer@example.invalid',name:'Buyer',fields:[{[fieldId]:'buyer@example.invalid'}],tickets:[]}])).rows[0].id);
   const ticket=Number((await db.query("insert into eshop.tickets(occasion,state,ticket_symbol) values($1,'ordered',gen_random_uuid()::text) returning id",[f.occasion])).rows[0].id);
   await db.query('insert into eshop.order_product_ticket("order",product,ticket) values($1,$2,$3)',[id,productId,ticket]);
   await db.query("update eshop.orders set data=data||jsonb_build_object('tickets',$2::jsonb) where id=$1",[id,JSON.stringify([{id:ticket,products:[{id:productId,price:100}]}])]);
   if(i===0){orderId=id;paymentId=pi;}else secondOrder=id;
  }
 }});
 const inspect=async id=>(await s.invoke('orders.inspect',{orderId:id})).orders[0];
 let state=await inspect(orderId);
 const edit={orderId,commandId:randomUUID(),expectedRevision:state.revision,changes:{note:'Approved note',responses:{[fieldId]:'updated@example.invalid'}}};
 const edited=await s.invoke('orders.update',edit);assert.equal(edited.replayed,false);
 assert.equal((await s.invoke('orders.update',edit)).replayed,true);
 state=await inspect(orderId);assert.equal(state.customer.email,'updated@example.invalid');
 const payment={orderId,commandId:randomUUID(),expectedRevision:state.revision,amount:'100.00',currency:'CZK',receivedAt:'2026-11-13T12:00:00Z'};
 s.loseNext();const lost=await s.call('payments.record',payment);assert.equal(lost.status,503);
 await s.reconnect();const paid=await s.invoke('payments.record',payment);assert.equal(paid.replayed,true);
 await s.db.query('RESET ROLE');assert.equal((await s.db.query('select paid::text amount from eshop.payment_info where id=$1',[paymentId])).rows[0].amount,'100.00');await s.db.query('SET LOCAL ROLE authenticated');
 state=await inspect(orderId);const send={orderId,commandId:randomUUID(),expectedRevision:state.revision};
 const queued=await s.invoke('orders.send_tickets',send);assert.equal(queued.delivery,'queued');
 assert.equal((await s.invoke('orders.send_tickets',send)).messageId,queued.messageId);
 await s.db.query('RESET ROLE');assert.equal((await s.db.query('select count(*)::int n from email_messages where message_id=$1',[queued.messageId])).rows[0].n,1);await s.db.query('SET LOCAL ROLE authenticated');
 state=await inspect(secondOrder);await s.command('orders.mark_paid',{orderId:secondOrder,expectedRevision:state.revision});
 assert.equal((await inspect(secondOrder)).state,'paid');
 state=await inspect(secondOrder);await s.command('orders.cancel',{orderId:secondOrder,expectedRevision:state.revision});
 assert.equal((await inspect(secondOrder)).state,'storno');
 const spare=await s.command('products.save',{product:{title:'Unused',price:'20.00',currency_code:'CZK',product_type:productType}});
 const catalog=await s.invoke('products.list');const product=catalog.products.find(p=>p.id===spare.productId);
 await s.command('products.delete',{productId:product.id,expectedVersion:product.aggregate_version});
});

test('HTTP SQL: occasion create/copy/delete and lifecycle recovery use one canonical intent per command',options,async t=>{
 const s=await postgresApi(t,{strong:true}),{f,db}=s;
 const request={unitId:f.unit,title:'Created through shared API',start:new Date(Date.now()+3600000).toISOString(),end:new Date(Date.now()+7200000).toISOString(),description:'Approved',commandId:randomUUID()};
 const created=await s.invoke('occasions.create',request);assert(created.occasionId);
 assert.deepEqual(await s.invoke('occasions.create',request),created);
 const copy={occasionId:created.occasionId,targetUnitId:f.unit,locale:'en',commandId:randomUUID()};
 const copied=await s.invoke('occasions.copy',copy);assert.notEqual(copied.occasionId,created.occasionId);
 assert.deepEqual(await s.invoke('occasions.copy',copy),copied);
 const remove={unitId:f.unit,occasionId:copied.occasionId,commandId:randomUUID()};
 const removed=await s.invoke('occasions.delete',remove);assert.equal(removed.state,'complete');
 assert.deepEqual(await s.invoke('occasions.delete',remove),removed);
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*)::int n from occasions where id=$1',[copied.occasionId])).rows[0].n,0);
});

test('HTTP SQL: blueprint saves and expanded seat block/hold release preserve one versioned intent',options,async t=>{
 const {setup:seatSetup}=await import('./seat-fixtures.mjs');
 const s=await postgresApi(t,{sqlSetup:seatSetup,seed:(db,f)=>db.query('insert into unit_users(unit,"user",is_manager,is_editor) values($1,$2,true,true) on conflict (unit,"user") do update set is_manager=true,is_editor=true',[f.unit,f.actor])});
 const {f,db,bindings}=s,spotIds=[bindings[0].spotId];
 const preview=await s.invoke('seats.preview_block',{blueprintId:f.blueprint,spotIds,blocked:true});assert.equal(preview.affectedSpotIds.length,2);
 const block={blueprintId:f.blueprint,spotIds,affectedSpotIds:preview.affectedSpotIds,layoutRevision:preview.layoutRevision,blocked:true,commandId:randomUUID()};
 s.loseNext();assert.equal((await s.call('seats.block',block)).status,503);
 const blocked=await s.invoke('seats.block',block);assert.equal(blocked.layoutRevision,preview.layoutRevision+1);
 assert.deepEqual(await s.invoke('seats.block',block),blocked);
 const unblock=await s.invoke('seats.preview_block',{blueprintId:f.blueprint,spotIds,blocked:false});
 await s.command('seats.block',{blueprintId:f.blueprint,spotIds,affectedSpotIds:unblock.affectedSpotIds,layoutRevision:unblock.layoutRevision,blocked:false});
 const before=await s.invoke('blueprints.inspect',{blueprintId:f.blueprint});const layout=structuredClone(before.layout);layout.canvas.width+=100;
 const draft={blueprintId:f.blueprint,title:'Approved geometry',expectedLayoutRevision:before.layoutRevision,layout,textResourceIds:before.textResourceIds,seatChanges:[],groupProductChanges:[],areaBindingChanges:[],commandId:randomUUID()};
 const saved=await s.invoke('blueprints.save',draft);assert.equal(saved.layoutRevision,before.layoutRevision+1);
 assert.deepEqual(await s.invoke('blueprints.save',draft),saved);
 await db.query('RESET ROLE');await db.query("update eshop.spots set secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' where id=$1",[bindings[1].spotId]);await db.query('SET LOCAL ROLE authenticated');
 const release=await s.invoke('seats.preview_release',{spotIds});assert.equal(release.canApply,true);
 const command={blueprintId:f.blueprint,spotIds,affectedSpotIds:release.affectedSpotIds,layoutRevision:release.layoutRevision,holdSnapshot:release.holdSnapshot,commandId:randomUUID()};
 const released=await s.invoke('seats.release_holds',command);assert.deepEqual(await s.invoke('seats.release_holds',command),released);
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*)::int n from eshop.spots where id=any($1) and secret is not null',[release.affectedSpotIds])).rows[0].n,0);
});

test('HTTP SQL: revocation after artwork commit cannot erase the replay identity from a lost outward response',options,async t=>{
 const s=await postgresApi(t),current=await s.invoke('ticket_layouts.inspect');
 const {request}=await import('./layout-fixture.mjs'),{canonicalPreview}=await import('./render-fixture.mjs');
 const rendered=await canonicalPreview();
 const input=request(s.service.config.profile,{occasionId:s.f.occasion,expectedVersion:current.aggregate_version,
   expectedLayout:current.appearance.layout??null,nextLayout:{schemaVersion:3,templates:{named:rendered.resolve.template}}});
 s.revokeNext();const refused=await s.call('ticket_layouts.save',input);assert.equal(refused.status,401);
 assert.equal((await refused.json()).outcome,'unknown');
 await s.reconnect();
 // The client never received a command UUID. Repeating its exact reviewed
 // request still resolves the original SQL receipt, including current rights.
 const recovered=await s.invoke('ticket_layouts.save',input);
 assert.equal(recovered.version,current.aggregate_version+1);
 const calls=s.rpcCalls.filter(c=>c.name==='save_delegated_ticket_layout');assert.equal(calls.length,2);
 assert.deepEqual(calls[0].args,calls[1].args);
 await s.db.query('RESET ROLE');assert.equal((await s.db.query('select count(*)::int n from client_mutation_receipts where command_id=$1',[recovered.commandId])).rows[0].n,1);
});
