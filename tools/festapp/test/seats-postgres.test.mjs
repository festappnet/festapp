import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {install,setup,paidSwap,swapState,paidAtomicSwap} from './seat-fixtures.mjs';
const options={skip:!process.env.FESTAPP_MCP_TEST_DATABASE_URL};
const ok=r=>{assert.equal(r.ok,true,JSON.stringify(r));return r.data;};

test('seat inspection and explicit expanded blocking share the canonical aggregate, preserve layout and replay one receipt',options,async t=>{
 const{db,f,bindings,doc,ex}=await setup(t);const one=ok(await ex.list());assert.equal(one.seats.length,2);assert(!JSON.stringify(one).includes('order_product_ticket'));assert(!JSON.stringify(one).includes('secret'));assert.equal(ok(await ex.list(one.nextCursor)).seats.length,2);
 const preview=ok(await ex.preview([bindings[0].spotId],true));assert.equal(preview.affectedSpotIds.length,2);assert.equal(preview.canApply,true);const commandId=randomUUID();ex.stats.lose=true;assert.equal((await ex.block(preview,commandId)).ok,false);const saved=ok(await ex.block(preview,commandId));assert.equal(saved.layoutRevision,2);assert.deepEqual(ok(await ex.block(preview,commandId)),saved);
 await db.query('RESET ROLE');assert.deepEqual((await db.query('select layout from eshop.blueprints where id=$1',[f.blueprint])).rows[0].layout,doc);assert.equal(Number((await db.query('select count(*) from eshop.blueprint_seat_bindings where blueprint=$1 and blocked',[f.blueprint])).rows[0].count),2);assert.equal(Number((await db.query('select count(*) from client_mutation_receipts where command_id=$1',[commandId])).rows[0].count),1);await db.query('SET LOCAL ROLE authenticated');
 assert.equal((await ex.block(preview)).error.code,'SEAT_REVISION_CHANGED_RELOAD_REQUIRED');const un=ok(await ex.preview([bindings[1].spotId],false));assert.equal(ok(await ex.block(un)).layoutRevision,3);
});

test('protected companions and changed confirmation reject the entire block; full UI save cannot block half an atomic unit',options,async t=>{
 const{db,f,bindings,doc,fx,ex}=await setup(t);const initial=ok(await ex.preview([bindings[0].spotId],true));const bad={...initial,affectedSpotIds:[bindings[0].spotId]};assert.equal((await ex.block(bad)).error.code,'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT');
 await db.query('RESET ROLE');await db.query("update eshop.spots set secret=gen_random_uuid(),secret_expiration_time=now()+interval '1 hour' where id=$1",[bindings[1].spotId]);await db.query('SET LOCAL ROLE authenticated');const held=ok(await ex.preview([bindings[0].spotId],true));assert.equal(held.canApply,false);assert.equal(held.seats.find(s=>s.spotId===bindings[1].spotId).state,'selected');assert.equal((await ex.block(initial)).error.code,'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT');
 const full={...fx.request,layout:doc,expected_layout_revision:1,seatChanges:[{...bindings[0],operation:'upsert',blocked:true}]};const result=(await db.query('select update_blueprint_client_sync_v1($1,$2) value',[full,randomUUID()])).rows[0].value;assert.equal(result.status,'rejected');assert.equal(result.data.reason,'BLUEPRINT_INCOMPLETE_BLOCK_SELECTION_UNIT');
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from eshop.blueprint_seat_bindings where blueprint=$1 and blocked',[f.blueprint])).rows[0].count),0);assert.equal((await db.query('select layout_revision from eshop.blueprints where id=$1',[f.blueprint])).rows[0].layout_revision,'1');
});

test('two connections: checkout hold and operational block serialize; neither can steal the other outcome',options,async t=>{
 const{db,f,fx,bindings,ex}=await setup(t,true);const buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);t.after(async()=>{await buyer.query('ROLLBACK');await buyer.end();});
 const preview=ok(await ex.preview([bindings[0].spotId],true));await db.query('COMMIT');const hold=randomUUID();
 await buyer.query('BEGIN');const acquired=(await buyer.query('select select_spot($1,$2,$3,true) value',[fx.formKey,hold,bindings[0].spotId])).rows[0].value;assert.equal(acquired.code,200,JSON.stringify(acquired));
 await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const pending=ex.block(preview);
 let blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'block waits on actual checkout lock');await buyer.query('COMMIT');assert.equal((await pending).error.code,'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT');await db.query('COMMIT');
 await buyer.query('select select_spot($1,$2,$3,false)',[fx.formKey,hold,bindings[0].spotId]);
 await db.query('BEGIN');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const fresh=ok(await ex.preview([bindings[0].spotId],true));ok(await ex.block(fresh));
 const checkout=buyer.query('select select_spot($1,$2,$3,true) value',[fx.formKey,hold,bindings[0].spotId]);
 blocked=false;await db.query('RESET ROLE');for(let i=0;i<100;i++){if((await db.query('select $1::int=any(pg_blocking_pids($2)) value',[db.processID,buyer.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'checkout waits on actual aggregate save lock');await db.query('COMMIT');assert.notEqual((await checkout).rows[0].value.code,200);
 await buyer.query('BEGIN');await buyer.query('update eshop.blueprints set title=title where id=$1',[f.blueprint]);
 await db.query('BEGIN');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const reading=ex.preview([bindings[0].spotId],false);
 blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'preview must reach actual blueprint read before revocation');
 await buyer.query('update occasion_users set is_editor=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await buyer.query('COMMIT');assert.equal((await reading).error.code,'FORBIDDEN');await db.query('ROLLBACK');

});

test('used tickets retain their orders; scoped seats expose the same UI lifecycle and require actual blueprint editor rights',options,async t=>{
 const{db,f,fx,bindings,ex}=await setup(t);await db.query('RESET ROLE');
 const order=Number((await db.query("insert into eshop.orders(occasion,order_sequence,order_symbol,state) values($1,next_order_sequence($1),generate_order_symbol(),'paid') returning id",[f.occasion])).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'used') returning id",[f.occasion])).rows[0].id);const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,fx.product])).rows[0].id);await db.query('update eshop.spots set order_product_ticket=$2 where id=$1',[bindings[1].spotId,item]);
 const original=(await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value;const link=(await db.query('select link from occasions where id=$1',[f.occasion])).rows[0].link;await db.query('SET LOCAL ROLE authenticated');
 const preview=ok(await ex.preview([bindings[0].spotId],true));assert.equal(preview.canApply,false);assert.equal(preview.seats.find(s=>s.spotId===bindings[1].spotId).state,'used');assert.equal((await ex.block(preview)).error.code,'SEAT_BLOCK_REJECTED_RELOAD_OR_RESELECT');
 const ui=(await db.query('select get_blueprint_for_edit($1) value',[link])).rows[0].value;assert.equal(ui.code,200,JSON.stringify(ui));const uiSpots=ui.data.spots;assert.equal(uiSpots.find(s=>s.id===bindings[1].spotId).state,'used');
 await db.query('RESET ROLE');assert.deepEqual((await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value,original);await db.query('update occasion_users set is_editor=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');assert.equal((await ex.list()).ok,true);assert.equal((await ex.preview([bindings[0].spotId],true)).error.code,'FORBIDDEN');
});

test('seat scope, complete selection validation, canonical source and helper ACL fail closed',options,async t=>{
 const{db,f,bindings,doc,ex}=await setup(t);await db.query('RESET ROLE');const foreign=Number((await db.query('select id from occasions where organization=$1 and id<>$2',[f.org,f.occasion])).rows[0].id);const foreignBp=Number((await db.query('insert into eshop.blueprints(occasion,organization,title,layout) values($1,$2,\'Foreign\',$3) returning id',[foreign,f.org,doc])).rows[0].id);await db.query('SET LOCAL ROLE authenticated');
 await db.query('SAVEPOINT denied_bp');await assert.rejects(db.query('select get_blueprint_seats($1,$2,$3,$4)',[f.occasion,f.org,f.unit,foreignBp]),e=>e.code==='42501');await db.query('ROLLBACK TO SAVEPOINT denied_bp');await db.query('RELEASE SAVEPOINT denied_bp');
 const scope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+99999});assert.equal((await ex.list()).error.code,'FORBIDDEN');ex.owner.delegatedContext=scope;assert.equal((await ex.preview([bindings[0].spotId,bindings[0].spotId],true)).error.code,'INVALID_INPUT');
 await db.query('RESET ROLE');await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const owners=['lock_blueprint_inventory_internal','blueprint_spot_facts_internal','check_blueprint_block_changes_internal','check_blueprint_admin_scope_internal','blueprint_admin_seat_rows_internal','get_blueprint_seats','blueprint_block_selection_internal','preview_blueprint_seat_block','block_blueprint_seats','save_blueprint_layout_impl_internal','save_blueprint_layout_internal_v1','get_blueprint_for_edit','blueprint_hold_snapshot_internal','blueprint_hold_selection_internal','preview_blueprint_hold_release','release_blueprint_holds','release_blueprint_holds_command_internal','apply_blueprint_seat_swap_internal','swap_blueprint_seats_command_internal','swap_spot_tickets_client_sync_v1','preview_blueprint_swap','preview_blueprint_seat_swap','swap_blueprint_seats','check_blueprint_swap_scope_internal','lock_spot_assignment_scope_internal','lock_spot_assignment_scope_internal_v1','apply_blueprint_seat_pair_locked_internal','project_order_amount_changes_internal','order_payment_snapshot_internal'];const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');const assertions=contract.split('\n').filter(l=>owners.some(n=>l.includes("to_regprocedure('public."+n+'(')));assert.equal(assertions.length,Number((await db.query("select count(*) from pg_proc where pronamespace='public'::regnamespace and proname=any($1)",[owners])).rows[0].count));await db.query('DO $$ BEGIN\n'+assertions.join('\n')+'\nEND $$;');
 for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,'block_blueprint_seats(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,boolean,uuid)','execute') allowed",[role])).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('authenticated','blueprint_spot_facts_internal(bigint,bigint[],timestamptz)','execute') allowed")).rows[0].allowed,false);
});

for(const name of ['layout_integration_test.sql','authorization_test.sql','finance_integration_test.sql'])test('blueprint regression: '+name,options,async t=>{
 const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);await db.query('SET LOCAL ROLE postgres');await db.query("select set_config('request.jwt.claim.role','service_role',true)");await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));await db.query(await readFile(new URL('../../../database/tests/blueprint/'+name,import.meta.url),'utf8'));
});

test('hold release binds the confirmed reservation identity; old receipt replay cannot release a later buyer',options,async t=>{
 const{db,f,bindings,fx}=await setup(t);const secret=randomUUID();const held=(await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,secret,bindings[0].spotId])).rows[0].v;assert.equal(held.code,200);
 const preview=(await db.query('select preview_blueprint_hold_release($1,$2,$3,$4) v',[f.occasion,f.org,f.unit,[bindings[0].spotId]])).rows[0].v;assert.equal(preview.affectedSpotIds.length,2);assert.equal(preview.activeHoldCount,2);assert.equal(preview.canApply,true);assert(!JSON.stringify(preview).includes(secret));
 const commandId=randomUUID(),args=[f.occasion,f.org,f.unit,f.blueprint,preview.requestedSpotIds,preview.affectedSpotIds,preview.layoutRevision,preview.holdSnapshot,commandId];
 const done=(await db.query('select release_blueprint_holds($1,$2,$3,$4,$5,$6,$7,$8,$9) v',args)).rows[0].v;assert.equal(done.status,'applied',JSON.stringify(done));assert.equal(done.data.releasedCount,2);assert.equal(done.sync,undefined);
 const laterSecret=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,laterSecret,bindings[0].spotId])).rows[0].v.code,200);
 const replay=(await db.query('select release_blueprint_holds($1,$2,$3,$4,$5,$6,$7,$8,$9) v',args)).rows[0].v;assert.deepEqual(replay,done);
 const stale=(await db.query('select release_blueprint_holds($1,$2,$3,$4,$5,$6,$7,$8,$9) v',[...args.slice(0,8),randomUUID()])).rows[0].v;assert.equal(stale.status,'rejected');assert.equal(stale.data.reason,'BLUEPRINT_HOLDS_CHANGED');
 await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from eshop.spots where blueprint=$1 and secret=$2',[f.blueprint,laterSecret])).rows[0].count),2);
});

test('MCP hold preview/release uses the same receipt, separate order-editor role and safe uncertain replay',options,async t=>{
 const{db,f,bindings,fx,ex}=await setup(t);await db.query('RESET ROLE');await db.query('update occasion_users set is_editor=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const secret=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,secret,bindings[0].spotId])).rows[0].v.code,200);
 assert.equal((await ex.preview([bindings[0].spotId],true)).error.code,'FORBIDDEN');const preview=ok(await ex.previewRelease([bindings[0].spotId]));assert.equal(preview.activeHoldCount,2);assert(!JSON.stringify(preview).includes(secret));
 const commandId=randomUUID();ex.stats.lose=true;assert.equal((await ex.release(preview,commandId)).ok,false);
 const later=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,later,bindings[0].spotId])).rows[0].v.code,200);
 const saved=ok(await ex.release(preview,commandId));
 assert.equal(ex.stats.payloadBytes.filter(p=>p.rpc==='preview_blueprint_hold_release').length,1,'one scoped preview RPC, no separate joins from MCP');
 assert.equal(ex.stats.payloadBytes.filter(p=>p.rpc==='release_blueprint_holds').length,2,'one RPC per write attempt, uncertain retry uses its receipt');
 assert(ex.stats.payloadBytes.every(p=>p.bytes<8192),'lean SQL responses contain no full editor/cache projection');
 t.diagnostic('Serialized SQL JSON bytes for two-seat atomic unit: '+JSON.stringify(ex.stats.payloadBytes));
 assert.equal(saved.releasedCount,2);assert.equal(saved.layoutRevision,preview.layoutRevision);assert.equal((await ex.release(preview)).error.code,'SEAT_HOLDS_CHANGED_NEW_PREVIEW_REQUIRED');await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from eshop.spots where blueprint=$1 and secret=$2',[f.blueprint,later])).rows[0].count),2);
});

test('pre-extraction hold receipts replay unchanged and preserve later buyer holds',options,async t=>{
 const{db,f,bindings,fx}=await setup(t);await db.query('RESET ROLE');const historical=await readFile(new URL('../../../supabase/migrations/20261021100000_canonical_authorization.sql',import.meta.url),'utf8');const definition=historical.match(/CREATE OR REPLACE FUNCTION public\.release_blueprint_holds_client_sync_v1\([\s\S]*?\$\$;/)?.[0];assert(definition);await db.query(definition);await db.query('SET LOCAL ROLE authenticated');
 const first=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,first,bindings[0].spotId])).rows[0].v.code,200);const commandId=randomUUID();const original=(await db.query('select release_blueprint_holds_client_sync_v1($1,$2) v',[[bindings[0].spotId],commandId])).rows[0].v;assert.equal(original.status,'applied');
 const later=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,later,bindings[0].spotId])).rows[0].v.code,200);await db.query('RESET ROLE');await db.query(await readFile(new URL('../../../database/functions/eshop/release_blueprint_holds_client_sync_v1.sql',import.meta.url),'utf8'));await db.query('SET LOCAL ROLE authenticated');assert.deepEqual((await db.query('select release_blueprint_holds_client_sync_v1($1,$2) v',[[bindings[0].spotId],commandId])).rows[0].v,original);await db.query('RESET ROLE');assert.equal(Number((await db.query('select count(*) from eshop.spots where blueprint=$1 and secret=$2',[f.blueprint,later])).rows[0].count),2);
});


test('hold release fails closed for incomplete confirmation, foreign scope, used seats and direct helper access',options,async t=>{
 const{db,f,bindings,fx,ex}=await setup(t);
 const preview=ok(await ex.previewRelease([bindings[0].spotId]));
 assert.equal((await ex.release({...preview,affectedSpotIds:[bindings[0].spotId]})).error.code,'SEAT_RELEASE_REJECTED_NEW_PREVIEW_REQUIRED');
 const originalScope=ex.owner.delegatedContext;ex.owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+99999});
 assert.equal((await ex.previewRelease([bindings[0].spotId])).error.code,'FORBIDDEN');
 assert.equal((await ex.release(preview)).error.code,'FORBIDDEN');ex.owner.delegatedContext=originalScope;
 await db.query('RESET ROLE');
 const order=Number((await db.query("insert into eshop.orders(occasion,order_sequence,order_symbol,state) values($1,next_order_sequence($1),generate_order_symbol(),'paid') returning id",[f.occasion])).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'used') returning id",[f.occasion])).rows[0].id);
 const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,fx.product])).rows[0].id);
 await db.query('update eshop.spots set order_product_ticket=$2 where id=$1',[bindings[1].spotId,item]);
 const before=(await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value;
 for(const signature of ['blueprint_hold_snapshot_internal(bigint,bigint[])','blueprint_hold_selection_internal(bigint,bigint,bigint[],integer)','release_blueprint_holds_command_internal(bigint[],uuid,bigint[],bigint,text)'])
  for(const role of ['anon','authenticated','service_role'])assert.equal((await db.query("select has_function_privilege($1,$2,'execute') allowed",[role,signature])).rows[0].allowed,false,role+' cannot invoke '+signature);
 for(const signature of ['preview_blueprint_hold_release(bigint,bigint,bigint,bigint[],boolean)','release_blueprint_holds(bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean)'])
  for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,$2,'execute') allowed",[role,signature])).rows[0].allowed,false);
 await db.query('SET LOCAL ROLE authenticated');
 const protectedPreview=ok(await ex.previewRelease([bindings[0].spotId]));assert.equal(protectedPreview.canApply,false);assert.equal(protectedPreview.seats.find(s=>s.spotId===bindings[1].spotId).state,'used');
 assert.equal((await ex.release(protectedPreview)).error.code,'SEAT_RELEASE_REJECTED_NEW_PREVIEW_REQUIRED');
 await db.query('RESET ROLE');assert.deepEqual((await db.query('select to_jsonb(o) value from eshop.orders o where id=$1',[order])).rows[0].value,before);
 assert.equal(Number((await db.query('select order_product_ticket from eshop.spots where id=$1',[bindings[1].spotId])).rows[0].order_product_ticket),item);
});


test('two connections: confirmed hold release waits for checkout and rejects a replacement buyer without clearing it',options,async t=>{
 const{db,f,fx,bindings,ex}=await setup(t,true);
 const buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);t.after(async()=>{await buyer.query('ROLLBACK');await buyer.end();});
 const first=randomUUID();assert.equal((await db.query('select select_spot($1,$2,$3,true) v',[fx.formKey,first,bindings[0].spotId])).rows[0].v.code,200);
 const preview=ok(await ex.previewRelease([bindings[0].spotId]));await db.query('COMMIT');
 await buyer.query('BEGIN');assert.equal((await buyer.query('select select_spot($1,$2,$3,false) v',[fx.formKey,first,bindings[0].spotId])).rows[0].v.code,200);
 const later=randomUUID();assert.equal((await buyer.query('select select_spot($1,$2,$3,true) v',[fx.formKey,later,bindings[0].spotId])).rows[0].v.code,200);
 await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const pending=ex.release(preview);let blocked=false;
 for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert(blocked,'release waits on actual checkout lock');await buyer.query('COMMIT');
 assert.equal((await pending).error.code,'SEAT_HOLDS_CHANGED_NEW_PREVIEW_REQUIRED');await db.query('COMMIT');
 assert.equal(Number((await buyer.query('select count(*) from eshop.spots where blueprint=$1 and secret=$2',[f.blueprint,later])).rows[0].count),2);
 // Permission can be revoked while the request waits, after its initial check.
 await db.query('BEGIN');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const fresh=ok(await ex.previewRelease([bindings[0].spotId]));await db.query('COMMIT');
 await buyer.query('BEGIN');await buyer.query('select lock_blueprint_scope_internal($1)',[[f.occasion]]);
 await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');
 const revokedCommand=randomUUID(),waiting=ex.release(fresh,revokedCommand);blocked=false;
 for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert(blocked,'release passed its early check before role revocation');
 await buyer.query('update occasion_users set is_editor=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await buyer.query('COMMIT');
 assert.equal((await waiting).error.code,'FORBIDDEN');await db.query('COMMIT');
 assert.equal(Number((await buyer.query('select count(*) from eshop.spots where blueprint=$1 and secret=$2',[f.blueprint,later])).rows[0].count),2);
 assert.equal(Number((await buyer.query('select count(*) from client_mutation_receipts where command_id=$1',[revokedCommand])).rows[0].count),0);
});

test('confirmed swap previews actual money without writes, commits once and replays the original effect',options,async t=>{
 const s=await paidSwap(t),before=await swapState(s),p=await s.preview();assert.equal(p.code,200,JSON.stringify(p));
 assert.equal(p.orders.length,1);assert.equal(Number(p.orders[0].beforeAmount),100);assert.equal(Number(p.orders[0].afterAmount),150);assert.equal(Number(p.orders[0].delta),50);assert.equal(typeof p.orders[0].delta,'string');
 assert(!JSON.stringify(p).includes('private-swap@example.invalid'));assert(p.seats.every(x=>!Object.hasOwn(x,'customer')));
 assert.deepEqual(await swapState(s),before,'preview rolls back order, money, allocation and history');assert.equal((await s.preview()).confirmationHash,p.confirmationHash,'preview hash ignores transient timestamps/history sequence IDs');
 const commandId=randomUUID(),done=await s.apply(p,commandId);assert.equal(done.status,'applied',JSON.stringify(done));assert.equal(done.sync,undefined);assert.equal(Number(done.data.orders[0].afterAmount),150);
 const after=await swapState(s);assert.deepEqual(after.blueprint,before.blueprint);assert.equal(Number(after.order.price),150);assert.equal(Number(after.payment.amount),150);assert.equal(after.order.state,'ordered');assert.equal(Number(after.spots.find(x=>Number(x.id)===s.second).order_product_ticket),s.item);
 assert.deepEqual(await s.apply(p,commandId),done);assert.deepEqual(await swapState(s),after,'receipt replay must not swap back');
 const changed=await s.apply(p);assert.equal(changed.status,'rejected');assert.equal(changed.data.reason,'BLUEPRINT_SWAP_CHANGED');assert.deepEqual(await swapState(s),after,'stale fresh command rolls back its attempted commercial effects');
});

test('confirmed swap rejects changed price, incomplete groups and used tickets without partial money/history changes',options,async t=>{
 const s=await paidSwap(t),p=await s.preview();await s.db.query('RESET ROLE');await s.db.query('update eshop.products set price=175 where id=$1',[s.product]);await s.db.query('SET LOCAL ROLE authenticated');
 const before=await swapState(s),changed=await s.apply(p);assert.equal(changed.data.reason,'BLUEPRINT_SWAP_CHANGED');assert.deepEqual(await swapState(s),before);
 const fresh=await s.preview();assert.equal(Number(fresh.orders[0].afterAmount),175);
 const wrong=await s.apply({...fresh,targetSpotIds:[s.first]});assert.equal(wrong.data.reason,'BLUEPRINT_SWAP_CHANGED');assert.deepEqual(await swapState(s),before);
 await s.db.query('RESET ROLE');await s.db.query("update eshop.tickets set state='used' where id=$1",[s.ticket]);await s.db.query('SET LOCAL ROLE authenticated');
 const usedBefore=await swapState(s),used=await s.apply(fresh);assert.equal(used.status,'rejected');assert.equal(used.data.reason,'BLUEPRINT_SWAP_CHANGED');assert.deepEqual(await swapState(s),usedBefore);
 // Existing UI/domain permits a used singleton swap; only used atomic units
 // are forbidden. Preserve that policy, but show state and invalidate stale consent.
 const usedPreview=await s.preview();assert.equal(usedPreview.code,200);assert.equal(usedPreview.seats.find(x=>x.spotId===s.first).state,'used');
});

test('legacy swap receipts retain their original fingerprint and do not execute again after extraction',options,async t=>{
 const s=await paidSwap(t);await s.db.query('RESET ROLE');
 const legacyBody=await readFile(new URL('../../../supabase/migrations/20261022180000_stripe_checkout_ingest.sql',import.meta.url),'utf8');
 const legacyReceipt=await readFile(new URL('../../../supabase/migrations/20261021100000_canonical_authorization.sql',import.meta.url),'utf8');
 const pair=legacyBody.match(/CREATE OR REPLACE FUNCTION public\.swap_spot_pair_internal_v1\([\s\S]*?\$\$;/)?.[0];
 const domain=legacyBody.match(/CREATE OR REPLACE FUNCTION public\.swap_spot_tickets_internal_v1\([\s\S]*?\$\$;/)?.[0];
 const receipt=legacyReceipt.match(/CREATE OR REPLACE FUNCTION public\.swap_spot_tickets_client_sync_v1\([\s\S]*?\$function\$;/)?.[0];assert(pair&&domain&&receipt);await s.db.query(pair);await s.db.query(domain);await s.db.query(receipt);await s.db.query('SET LOCAL ROLE authenticated');
 const commandId=randomUUID(),original=(await s.db.query('select swap_spot_tickets_client_sync_v1($1,$2,$3) v',[s.first,s.second,commandId])).rows[0].v;assert.equal(original.status,'applied');const after=await swapState(s);
 await s.db.query('RESET ROLE');await s.db.query(await readFile(new URL('../../../supabase/migrations/20261023233000_confirmed_blueprint_seat_swap.sql',import.meta.url),'utf8'));await s.db.query('SET LOCAL ROLE authenticated');
 assert.deepEqual((await s.db.query('select swap_spot_tickets_client_sync_v1($1,$2,$3) v',[s.first,s.second,commandId])).rows[0].v,original);assert.deepEqual(await swapState(s),after);
});


test('MCP swap uses confirmed SQL money, scoped order rights and one uncertain receipt; private/retired routes stay closed',options,async t=>{
 const s=await paidSwap(t),before=await swapState(s),p=ok(await s.ex.previewSwap(s.first,s.second));
 assert.equal(Number(p.orders[0].delta),50);assert(!JSON.stringify(p).includes('private-swap@example.invalid'));assert.deepEqual(await swapState(s),before);
 const originalScope=s.ex.owner.delegatedContext;s.ex.owner.delegatedContext=async()=>({organizationId:s.f.org,unitId:s.f.unit+99999});assert.equal((await s.ex.previewSwap(s.first,s.second)).error.code,'FORBIDDEN');assert.equal((await s.ex.swap(p)).error.code,'FORBIDDEN');s.ex.owner.delegatedContext=originalScope;
 const commandId=randomUUID();s.ex.stats.lose=true;assert.equal((await s.ex.swap(p,commandId)).ok,false);const done=ok(await s.ex.swap(p,commandId));assert.equal(Number(done.orders[0].afterAmount),150);const after=await swapState(s);assert.deepEqual(ok(await s.ex.swap(p,commandId)),done);assert.deepEqual(await swapState(s),after);
 assert.equal((await s.ex.swap(p)).error.code,'SEAT_SWAP_CHANGED_NEW_PREVIEW_REQUIRED');assert.deepEqual(await swapState(s),after);
 t.diagnostic('Serialized swap SQL JSON bytes: '+JSON.stringify(s.ex.stats.payloadBytes));
 await s.db.query('RESET ROLE');assert.equal((await s.db.query("select to_regprocedure('public.swap_spot_tickets_internal_v1(bigint,bigint)') p")).rows[0].p,null);
 for(const signature of ['apply_blueprint_seat_swap_internal(bigint,bigint)','apply_blueprint_seat_pair_locked_internal(bigint,bigint)','check_blueprint_swap_scope_internal(bigint,bigint[])','lock_spot_assignment_scope_internal(bigint[],bigint[],boolean)','swap_blueprint_seats_command_internal(bigint,bigint,uuid,jsonb)'])for(const role of ['anon','authenticated','service_role'])assert.equal((await s.db.query("select has_function_privilege($1,$2,'execute') allowed",[role,signature])).rows[0].allowed,false);
 for(const signature of ['preview_blueprint_seat_swap(bigint,bigint,bigint,bigint,bigint,bigint,boolean)','swap_blueprint_seats(bigint,bigint,bigint,bigint,bigint,bigint,bigint[],bigint[],bigint,text,uuid,boolean)'])for(const role of ['anon','service_role'])assert.equal((await s.db.query("select has_function_privilege($1,$2,'execute') allowed",[role,signature])).rows[0].allowed,false);
});

test('two connections: swap waits for checkout and role revocation, preserving holds and all financial facts',options,async t=>{
 const s=await paidSwap(t,true),{db,f,ex}=s,buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let pending;
 try{
  const before=await swapState(s),p=ok(await ex.previewSwap(s.first,s.second));await db.query('COMMIT');
  const hold=randomUUID();await buyer.query('BEGIN');assert.equal((await buyer.query('select select_spot($1,$2,$3,true) v',[s.fx.formKey,hold,s.second])).rows[0].v.code,200);
  await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');pending=ex.swap(p);
  let blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'swap waits on actual checkout lock');await buyer.query('COMMIT');assert.equal((await pending).error.code,'SEAT_SWAP_REJECTED_NEW_PREVIEW_REQUIRED');pending=null;await db.query('COMMIT');
  const after=await swapState(s);for(const key of ['order','payment','items','history'])assert.deepEqual(after[key],before[key],key+' unchanged');assert.equal(after.spots.find(x=>Number(x.id)===s.second).secret,hold);await db.query('COMMIT');
  assert.equal((await buyer.query('select select_spot($1,$2,$3,false) v',[s.fx.formKey,hold,s.second])).rows[0].v.code,200);
  await db.query('BEGIN');await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const fresh=ok(await ex.previewSwap(s.first,s.second));await db.query('COMMIT');
  await buyer.query('BEGIN');await buyer.query('select lock_blueprint_scope_internal($1)',[[f.occasion]]);
  await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const commandId=randomUUID();pending=ex.swap(fresh,commandId);
  blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'swap passed initial permission check before revocation');
  await buyer.query('update occasion_users set is_editor=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await buyer.query('COMMIT');assert.equal((await pending).error.code,'FORBIDDEN');pending=null;await db.query('COMMIT');
  assert.equal(Number((await buyer.query('select count(*) from client_mutation_receipts where command_id=$1',[commandId])).rows[0].count),0);
  const revoked=await swapState(s);for(const key of ['order','payment','items','history'])assert.deepEqual(revoked[key],before[key],key+' unchanged after revocation');
 }finally{await buyer.query('ROLLBACK');await buyer.end();if(pending)await pending.catch(()=>{});}
});


test('atomic four-seat swap aggregates each order once and rolls back an earlier member when the later member fails',options,async t=>{
 const s=await paidAtomicSwap(t),{db,f,source,target}=s;
 await db.query('RESET ROLE');await db.query("set local track_functions='all'");await db.query('SET LOCAL ROLE authenticated');
 const measured=['lock_spot_assignment_scope_internal','lock_spot_assignment_scope_internal_v1','swap_spot_pair_internal_v1','apply_blueprint_seat_pair_locked_internal'];
 const beforeCalls=new Map((await db.query('select funcname,calls from pg_stat_xact_user_functions where funcname=any($1)',[measured])).rows.map(r=>[r.funcname,Number(r.calls)]));
 const p=(await db.query('select preview_blueprint_seat_swap($1,$2,$3,$4,$5,$6) v',[f.occasion,f.org,f.unit,f.blueprint,source[0].spotId,target[0].spotId])).rows[0].v;assert.equal(p.code,200,JSON.stringify(p));assert.equal(p.seats.length,4);assert.equal(p.orders.length,1);assert.equal(Number(p.orders[0].beforeAmount),200);assert.equal(Number(p.orders[0].afterAmount),300);assert.equal(Number(p.orders[0].delta),100);
 t.diagnostic('Actual parent-lock/pair calls for one four-seat paid preview: '+JSON.stringify((await db.query('select funcname,calls from pg_stat_xact_user_functions where funcname=any($1)',[measured])).rows.map(r=>({name:r.funcname,calls:Number(r.calls)-(beforeCalls.get(r.funcname)??0)}))));
 const apply=async()=> (await db.query('select swap_blueprint_seats($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) v',[f.occasion,f.org,f.unit,f.blueprint,source[0].spotId,target[0].spotId,p.sourceSpotIds,p.targetSpotIds,p.layoutRevision,p.confirmationHash,randomUUID()])).rows[0].v;
 await db.query('RESET ROLE');const euro=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) select occasion,product_type,'Later member EUR',150,'EUR' from eshop.products where id=$1 returning id",[s.fx.product])).rows[0].id);await db.query('update eshop.spots set product=$2 where id=$1',[target[1].spotId,euro]);await db.query('SET LOCAL ROLE authenticated');
 const failedBefore=await swapState(s),failed=await apply();assert.equal(failed.status,'rejected');assert.equal(failed.data.reason,'BLUEPRINT_SWAP_REJECTED');assert.deepEqual(await swapState(s),failedBefore,'the first successful pair must also roll back when the second pair fails');
 await db.query('RESET ROLE');await db.query('update eshop.spots set product=$2 where id=$1',[target[1].spotId,s.product]);await db.query('SET LOCAL ROLE authenticated');const before=await swapState(s),done=await apply();assert.equal(done.status,'applied',JSON.stringify(done));const after=await swapState(s);assert.equal(Number(after.order.price),300);assert.equal(Number(after.payment.amount),300);assert.deepEqual(after.blueprint,before.blueprint);assert(after.spots.filter(x=>source.some(b=>b.spotId===Number(x.id))).every(x=>x.order_product_ticket===null));assert.equal(after.spots.filter(x=>target.some(b=>b.spotId===Number(x.id))&&x.order_product_ticket!==null).length,2);
});

test('two connections: swap preview takes form/order parents before blueprint rows',options,async t=>{
 const s=await paidSwap(t,true),{db,f}=s,buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let reading;
 try{
  await db.query('COMMIT');await buyer.query('BEGIN');await buyer.query("set local statement_timeout='500ms'");await buyer.query('select id from forms where id=$1 for update',[s.fx.form]);
  await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');reading=s.ex.previewSwap(s.first,s.second);
  let blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'preview waits on the canonical order form parent');
  // Same row-lock order used by ordinary order/product editing. An early
  // blueprint SHARE lock would invert it and make this request time out.
  await buyer.query('select id from eshop.blueprints where id=$1 for update',[f.blueprint]);await buyer.query('COMMIT');const preview=ok(await reading);reading=null;assert.equal(Number(preview.orders[0].delta),50);await db.query('COMMIT');
 }finally{await buyer.query('ROLLBACK');await buyer.end();if(reading)await reading.catch(()=>{});}
});


test('two connections: a ticket used while waiting cannot move an atomic group through the legacy adapter',options,async t=>{
 const s=await paidAtomicSwap(t,true),{db,f}=s,buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);let waiting;
 try{
  const before=await swapState(s);await db.query('COMMIT');await buyer.query('BEGIN');await buyer.query("update eshop.tickets set state='used' where id=$1",[s.ticket]);
  await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');
  waiting=db.query('select swap_spot_tickets_client_sync_v1($1,$2,$3) v',[s.first,s.second,randomUUID()]).then(r=>({value:r.rows[0].v}),error=>({error}));
  let blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) value',[buyer.processID,db.processID])).rows[0].value){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}assert(blocked,'swap waits on the actual used-ticket transition');await buyer.query('COMMIT');
  const result=await waiting;waiting=null;assert.equal(result.error?.code,'23514');assert.equal(result.error?.message,'BLUEPRINT_SELECTION_UNIT_USED');await db.query('ROLLBACK');
  const after=await swapState(s);for(const key of ['order','payment','items','history','blueprint','spots'])assert.deepEqual(after[key],before[key],key+' unchanged by rejected legacy intent');
 }finally{await buyer.query('ROLLBACK');await buyer.end();if(waiting)await waiting.catch(()=>{});}
});

test('foreign product, ticket or order parents cannot escape a narrowed swap scope',options,async t=>{
 const s=await paidSwap(t),p=ok(await s.ex.previewSwap(s.first,s.second));await s.db.query('RESET ROLE');
 const foreign=Number((await s.db.query('select id from occasions where organization=$1 and id<>$2 order by id limit 1',[s.f.org,s.f.occasion])).rows[0].id);
 const type=Number((await s.db.query("insert into eshop.product_types(occasion,title,type) values($1,'Foreign type','spot') returning id",[foreign])).rows[0].id);
 const product=Number((await s.db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) values($1,$2,'Foreign private SKU',150,'CZK') returning id",[foreign,type])).rows[0].id);
 for(const [sql,args] of [['update eshop.spots set product=$2 where id=$1',[s.second,product]],['update eshop.tickets set occasion=$2 where id=$1',[s.ticket,foreign]],['update eshop.orders set occasion=$2 where id=$1',[s.order,foreign]]]){
  await s.db.query('SAVEPOINT foreign_parent');await s.db.query(sql,args);await s.db.query('SET LOCAL ROLE authenticated');const before=await swapState(s);
  const read=await s.ex.previewSwap(s.first,s.second),write=await s.ex.swap(p);assert.equal(read.error.code,'FORBIDDEN');assert.equal(write.error.code,'FORBIDDEN');assert(!JSON.stringify(read).includes('Foreign private SKU'));assert.deepEqual(await swapState(s),before);
  await s.db.query('RESET ROLE');await s.db.query('ROLLBACK TO SAVEPOINT foreign_parent');await s.db.query('RELEASE SAVEPOINT foreign_parent');
 }
});


test('unknown order money cannot become a zero quote or commit before a typed response fails',options,async t=>{
 const s=await paidSwap(t);await s.db.query('RESET ROLE');await s.db.query('update eshop.orders set price=NULL where id=$1',[s.order]);await s.db.query('SET LOCAL ROLE authenticated');
 const before=await swapState(s),preview=await s.preview();assert.equal(preview.code,409);assert.equal(preview.reason,'BLUEPRINT_SWAP_MONEY_UNAVAILABLE');assert.deepEqual(await swapState(s),before);
 // A legacy read can still return its historical shape. Its opaque token cannot
 // force incomplete money through the new confirmed command.
 const legacy=(await s.db.query('select preview_blueprint_swap($1,$2) v',[s.first,s.second])).rows[0].v;assert.equal(legacy.code,200);assert.equal(legacy.orders[0].beforeAmount,null);
 const rejected=await s.apply({...legacy,layoutRevision:legacy.blueprints[0].revision});assert.equal(rejected.status,'rejected');assert.equal(rejected.data.reason,'BLUEPRINT_SWAP_REJECTED');assert.deepEqual(await swapState(s),before);
});
