import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
export async function install(db){
 await db.query('RESET ROLE');
 const declared=new Set();
 // Current main domain guards/producers must exist before the final forward
 // owner is exercised. Schema is additive and remains inside each fixture TX.
 const prerequisites=['notification_center/schema.sql','notification_center/core.sql','notification_center/orders.sql',
  'notification_center/capacity.sql','notification_center/email.sql','notification_center/maintenance.sql','notification_center/bank.sql',
  'eshop_ticket_batches/schema.sql','eshop_ticket_batches/guards.sql','eshop_orders/check_order_is_mutable.sql'];
 for(const file of prerequisites){
  let sql=await readFile(new URL('../../../database/functions/'+file,import.meta.url),'utf8');
  if(file==='notification_center/schema.sql'&&(await db.query("select to_regclass('public.notification_center_activation') present")).rows[0].present)continue;
  if(file==='notification_center/maintenance.sql'&&(await db.query("select to_regclass('public.notification_center_maintenance') present")).rows[0].present)sql=sql.slice(sql.indexOf('CREATE OR REPLACE FUNCTION'));
  await db.query(sql);for(const match of sql.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\s*\(/gi))declared.add(match[1]);
 }
 for(const file of ['20261023220000_blueprint_seat_operations.sql','20261023232000_confirmed_blueprint_hold_release.sql','20261023233000_confirmed_blueprint_seat_swap.sql','20261024023000_confirmed_blueprint_seat_orders.sql','20261024024000_confirmed_blueprint_ticket_cancellation.sql']){const sql=await readFile(new URL('../../../supabase/migrations/'+file,import.meta.url),'utf8');await db.query(sql);for(const match of sql.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\s*\(/gi))declared.add(match[1]);}
 const currentOwners=['blueprint/save.sql','eshop/materialize_ticket_products_internal_v1.sql','eshop/create_ticket_order.sql',
  'eshop/finalize_ticket_order.sql','eshop_orders/internal_storno_tickets_221.sql','eshop_orders/recalculate_order_payment_status.sql',
  'inventory/apply_allocations.sql','inventory/adjust_spot_capacity_for_pool.sql','emails/email_queue.sql','eshop_waitlist/fakturoid_recovery.sql'];
 for(const file of currentOwners){const sql=await readFile(new URL('../../../database/functions/'+file,import.meta.url),'utf8');await db.query(sql);for(const match of sql.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\s*\(/gi))declared.add(match[1]);}
 // Every declaration in this cut is installed by postgres on production.
 // The disposable postgres role cannot replace supabase_admin-owned routines;
 // install with the fixture owner, then align only these declared owners.
 const declaredRows=(await db.query("select format('ALTER FUNCTION %s OWNER TO postgres',p.oid::regprocedure) statement from pg_proc p where p.pronamespace='public'::regnamespace and p.proname=any($1)",[[...declared]])).rows;
 for(const row of declaredRows)await db.query(row.statement);
 await db.query(await readFile(new URL('../../../database/tests/blueprint/fixtures.sql',import.meta.url),'utf8'));await db.query('RESET ROLE');
 // Exact production metadata verified through protected read-only canonical
 // access: these eight existing functions are postgres-owned. New definer
 // wrappers also use the actual production migration role, not a queue bypass.
 await db.query('ALTER TABLE eshop.replacement_invoice_preparations OWNER TO postgres');
 for(const table of ['ticket_batches','ticket_batch_items','ticket_batch_document_parts']){await db.query(`ALTER TABLE eshop.${table} OWNER TO postgres`);await db.query(`GRANT SELECT,INSERT,UPDATE,DELETE ON eshop.${table} TO service_role`);}
 for(const row of (await db.query("select format('ALTER TABLE public.%I OWNER TO postgres',tablename) statement from pg_tables where schemaname='public' and tablename like 'notification_center_%'")).rows)await db.query(row.statement);
 const signatures=['confirm_blueprint_order_change_internal_v1(bigint[],jsonb)','storno_tickets_bulk_internal_v1(bigint[],boolean)',
  'update_order_and_tickets_to_storno(bigint)','create_ticket_order_internal_v1(jsonb)',
  'enqueue_ticket_order_confirmation_v1(uuid,bigint,jsonb,text)','enqueue_paid_order_tickets(bigint)',
  'cancel_order_email_intents(bigint)','replace_blueprint_order_client_sync_v1(bigint[],jsonb,uuid)',
  'preview_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,boolean)',
  'create_blueprint_seat_order(bigint,bigint,bigint,bigint,bigint[],jsonb,bigint[],bigint[],jsonb,text,uuid,boolean,uuid)'];
 const rows=(await db.query("select format('ALTER FUNCTION %s OWNER TO postgres',to_regprocedure('public.'||signature)) statement from unnest($1::text[]) signature where to_regprocedure('public.'||signature) is not null",[signatures])).rows;
 assert.equal(rows.length,signatures.length);for(const row of rows)await db.query(row.statement);
}

export async function setup(t,persistent=false){let root,f;const db=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);await db.query('BEGIN');t.after(async()=>{try{await db.query('ROLLBACK');if(persistent&&f&&(await db.query('select exists(select 1 from occasions where id=$1) present',[f.occasion])).rows[0].present)await cleanup(db,f,root);}finally{await db.end();}});await install(db);root=await fixture(db,1);const fx=(await db.query('select blueprint_test_fixture_internal($1) value',[root.org])).rows[0].value;f={...root,occasion:Number(fx.occasion),blueprint:Number(fx.blueprint),unit:Number((await db.query('select unit from occasions where id=$1',[fx.occasion])).rows[0].unit)};
 await db.query('update occasion_users set "user"=$2 where occasion=$1',[f.occasion,f.actor]);await db.query("select set_config('request.jwt.claim.sub',$1,true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');const saved=(await db.query('select update_blueprint_client_sync_v1($1,$2) value',[fx.request,randomUUID()])).rows[0].value;assert.equal(saved.status,'applied',JSON.stringify(saved));
 await db.query('RESET ROLE');const bindings=(await db.query('select blueprint_binding_projection_internal($1) value',[f.blueprint])).rows[0].value.seatBindings;
 const unit=randomUUID();const doc={...fx.request.layout,selectionUnits:[{id:unit,kind:'atomic',nodeIds:bindings.slice(0,2).map(b=>b.nodeId)}]};await db.query('update eshop.blueprints set layout=$2 where id=$1',[f.blueprint,doc]);await db.query('update eshop.blueprint_seat_bindings set selection_unit=$2 where blueprint=$1 and spot=any($3)',[f.blueprint,unit,bindings.slice(0,2).map(b=>b.spotId)]);await db.query('SET LOCAL ROLE authenticated');return{db,f,bindings,doc,fx,ex:executor(db,f)};}

export function executor(db,f,{invokeEdge}={}){
 const stats={calls:0,lose:false,payloadBytes:[]};
 const params={
  preview_blueprint_ticket_cancellation:['p_occasion','p_organization','p_unit','p_blueprint','p_spots'],
  cancel_blueprint_tickets:['p_occasion','p_organization','p_unit','p_blueprint','p_spots','p_tickets','p_confirmation_hash','p_command_id','p_editor'],
  get_blueprint_seats:['p_occasion','p_organization','p_unit','p_blueprint','p_after','p_limit'],
  preview_blueprint_seat_block:['p_occasion','p_organization','p_unit','p_blueprint','p_spots','p_blocked'],
  block_blueprint_seats:['p_occasion','p_organization','p_unit','p_blueprint','p_spots','p_affected_spots','p_expected_revision','p_blocked','p_command_id'],
  preview_blueprint_hold_release:['p_occasion','p_organization','p_unit','p_spots','p_editor'],
  release_blueprint_holds:['p_occasion','p_organization','p_unit','p_blueprint','p_spots','p_affected_spots','p_expected_revision','p_hold_snapshot','p_command_id','p_editor'],
  preview_blueprint_seat_swap:['p_occasion','p_organization','p_unit','p_blueprint','p_first','p_second','p_editor'],
  swap_blueprint_seats:['p_occasion','p_organization','p_unit','p_blueprint','p_first','p_second','p_source_spots','p_target_spots','p_expected_revision','p_confirmation_hash','p_command_id','p_editor'],
  preview_blueprint_seat_order:['p_occasion','p_organization','p_unit','p_blueprint','p_spots','p_input','p_editor'],
 };
 const client={rpc:async(name,a)=>{
  assert(Object.hasOwn(params,name),'known real seat RPC');stats.calls++;await db.query('SAVEPOINT rpc');
  try{const values=params[name].map(k=>a[k]??null),sql=`select ${name}(${values.map((_,i)=>'$'+(i+1)).join(',')}) value`;
   const data=(await db.query(sql,values)).rows[0].value;
   if(['block_blueprint_seats','release_blueprint_holds','swap_blueprint_seats','cancel_blueprint_tickets'].includes(name))assert.equal(data.sync,undefined);
   stats.payloadBytes.push({rpc:name,bytes:Buffer.byteLength(JSON.stringify(data),'utf8')});await db.query('RELEASE SAVEPOINT rpc');
   if(stats.lose&&['block_blueprint_seats','release_blueprint_holds','swap_blueprint_seats','cancel_blueprint_tickets'].includes(name)){stats.lose=false;return{error:{code:'ECONNRESET',status:503}};}
   return{data,error:null};
  }catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error:{code:error.code,status:error.code==='42501'?403:400}};}
 },functions:{invoke:async(name,options)=>{
   assert(invokeEdge,'Edge adapter must be explicitly provided; no live HTTP fallback');stats.calls++;
   const response=await invokeEdge(name,options);if(response.data)stats.payloadBytes.push({rpc:name,bytes:Buffer.byteLength(JSON.stringify(response.data),'utf8')});
   if(stats.lose){stats.lose=false;return{error:{code:'ECONNRESET',status:503}};}return response;
 }}};
 const owner={root:'/tmp/festapp-seat-operations',profile:{binding:'seat-fixture:'+f.actor,organizationId:f.org,tenantId:'fixture',name:'fixture',backendOrigin:'http://127.0.0.1:61022'},
  allowedOperations:['seats.list','seats.preview_block','seats.block','seats.preview_release','seats.release_holds','seats.preview_swap','seats.swap','seats.preview_order','seats.create_order','seats.preview_cancel','seats.cancel_tickets'],
  delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),authorized:action=>action(client,{userId:f.actor})};
 const ops=new Operations(owner);
 return{stats,owner,ops,
  previewOrder:(spotIds,inputData)=>ops.invoke('seats.preview_order',{occasionId:f.occasion,blueprintId:f.blueprint,spotIds,...(inputData?{inputData}:{})}),
  createOrder:(preview,inputData,commandId=randomUUID())=>ops.invoke('seats.create_order',{occasionId:f.occasion,blueprintId:f.blueprint,spotIds:preview.requestedSpotIds,actorId:preview.actorId,inputData,targetSpotIds:preview.quote.spotIds,affectedSpotIds:preview.quote.affectedSpotIds,blueprints:preview.quote.blueprints,confirmationHash:preview.confirmationHash,commandId}),
  previewSwap:(firstSpotId,secondSpotId)=>ops.invoke('seats.preview_swap',{occasionId:f.occasion,blueprintId:f.blueprint,firstSpotId,secondSpotId}),
  swap:(preview,commandId=randomUUID())=>ops.invoke('seats.swap',{occasionId:f.occasion,blueprintId:preview.blueprintId,firstSpotId:preview.firstSpotId,secondSpotId:preview.secondSpotId,sourceSpotIds:preview.sourceSpotIds,targetSpotIds:preview.targetSpotIds,layoutRevision:preview.layoutRevision,confirmationHash:preview.confirmationHash,commandId}),
  previewRelease:spotIds=>ops.invoke('seats.preview_release',{occasionId:f.occasion,spotIds}),
  release:(preview,commandId=randomUUID())=>ops.invoke('seats.release_holds',{occasionId:f.occasion,blueprintId:preview.blueprintId,spotIds:preview.requestedSpotIds,affectedSpotIds:preview.affectedSpotIds,layoutRevision:preview.layoutRevision,holdSnapshot:preview.holdSnapshot,commandId}),
  list:after=>ops.invoke('seats.list',{occasionId:f.occasion,blueprintId:f.blueprint,limit:2,...(after?{after}:{})}),
  preview:(spotIds,blocked)=>ops.invoke('seats.preview_block',{occasionId:f.occasion,blueprintId:f.blueprint,spotIds,blocked}),
  block:(preview,commandId=randomUUID())=>ops.invoke('seats.block',{occasionId:f.occasion,blueprintId:preview.blueprintId,spotIds:preview.requestedSpotIds,affectedSpotIds:preview.affectedSpotIds,layoutRevision:preview.layoutRevision,blocked:preview.blocked,commandId})};
}

export async function cleanup(db,f,root){
 await db.query('BEGIN');await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
 const occasions=[f.occasion,root.occasion];
 // Only this fenced fixture's synthetic pending orders are aborted for teardown.
 // No live provider is configured and the email worker is paused by the harness.
 await db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','service_role',true)");
 for(const row of (await db.query("select o.id,q.data->>'command_id' command from eshop.orders o join email_messages q on (q.data#>>'{ticket_order,order,id}')::bigint=o.id where o.occasion=any($1::bigint[]) and o.state='preparing_payment' and q.code='TICKET_ORDER_CONFIRMATION' and q.data->>'fakturoid_pending'='true'",[occasions])).rows)await db.query('select abort_fakturoid_ticket_order_v1($1,$2)',[row.id,row.command]);
 await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);
 await db.query('insert into unit_users(unit,"user",is_manager) values($1,$2,true) on conflict(unit,"user") do update set is_manager=true',[f.unit,f.actor]);
 for(const row of (await db.query('select id from eshop.orders where occasion=any($1::bigint[]) order by id',[occasions])).rows)await db.query('select delete_order_internal_v1($1)',[row.id]);
 await db.query('delete from client_mutation_receipts where occasion=any($1::bigint[])',[occasions]);
 for(const table of ['client_commit_items','client_commit_components'])await db.query(`delete from ${table} where commit_id in(select commit_id from client_commits where occasion=any($1::bigint[]))`,[occasions]);await db.query('delete from client_commits where occasion=any($1::bigint[])',[occasions]);await db.query("delete from client_aggregate_versions where scope_type='occasion' and scope_id=any($1::bigint[])",[occasions]);
 for(const oc of occasions)await db.query('select delete_occasion_internal_v1($1)',[oc]);
 await db.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[root.unit,f.org]);await db.query('delete from unit_users where unit=any($1::bigint[])',[[f.unit,root.unit]]);const accounts=(await db.query('delete from eshop.unit_bank_accounts where unit=any($1::bigint[]) returning bank_account',[[f.unit,root.unit]])).rows.map(r=>r.bank_account);await db.query('delete from eshop.bank_accounts where id=any($1::bigint[]) and not exists(select 1 from eshop.unit_bank_accounts u where u.bank_account=eshop.bank_accounts.id)',[accounts]);await db.query('delete from eshop.external_services where unit=any($1::bigint[])',[[f.unit,root.unit]]);await db.query('delete from units where organization=$1',[f.org]);await db.query('delete from user_info where id=$1',[f.actor]);await db.query('delete from auth.users where id=$1',[f.actor]);await db.query('delete from organizations where id=$1',[f.org]);await db.query('COMMIT');
}


export async function paidSwap(t,persistent=false){
 const state=await setup(t,persistent),{db,f,fx,bindings}=state;await db.query('RESET ROLE');
 const product=Number((await db.query("insert into eshop.products(occasion,product_type,title,price,currency_code) select occasion,product_type,'Expensive destination',150,'CZK' from eshop.products where id=$1 returning id",[fx.product])).rows[0].id);
 const first=bindings[2].spotId,second=bindings[3].spotId;
 await db.query('update eshop.spots set product=$2 where id=$1',[second,product]);
 const order=Number((await db.query('select allocate_ticket_order_identity_internal($1) id',[fx.form])).rows[0].id);
 const payment=Number((await db.query("insert into eshop.payment_info(amount,paid,currency_code) values(100,100,'CZK') returning id")).rows[0].id);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[f.occasion])).rows[0].id);
 const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[order,ticket,fx.product])).rows[0].id);
 await db.query("update eshop.orders set state='paid',price=100,payment_info=$2,data=jsonb_build_object('name','Private swap customer','email','private-swap@example.invalid','tickets',jsonb_build_array(jsonb_build_object('id',$3::bigint,'products',jsonb_build_array(_swap_spots_generate_product_json($4,$5))))) where id=$1",[order,payment,ticket,fx.product,first]);
 await db.query('update eshop.spots set order_product_ticket=$2 where id=$1',[first,item]);await db.query('SET LOCAL ROLE authenticated');
 return{...state,first,second,product,order,payment,ticket,item,
 preview:async()=> (await db.query('select preview_blueprint_seat_swap($1,$2,$3,$4,$5,$6) v',[f.occasion,f.org,f.unit,f.blueprint,first,second])).rows[0].v,
 apply:async(p,commandId=randomUUID())=>(await db.query('select swap_blueprint_seats($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) v',[f.occasion,f.org,f.unit,f.blueprint,first,second,p.sourceSpotIds,p.targetSpotIds,p.layoutRevision,p.confirmationHash,commandId])).rows[0].v};
}

export async function swapState(s){
 await s.db.query('RESET ROLE');const r=(await s.db.query(`select jsonb_build_object('order',(select to_jsonb(o) from eshop.orders o where id=$1),
 'payment',(select to_jsonb(p) from eshop.payment_info p where id=$2),
 'items',(select jsonb_agg(to_jsonb(i) order by id) from eshop.order_product_ticket i where i."order"=$1),
 'spots',(select jsonb_agg(to_jsonb(x) order by id) from eshop.spots x where id=any($3)),
 'history',(select coalesce(jsonb_agg(to_jsonb(h) order by id),'[]') from eshop.orders_history h where h."order"=$1),
 'blueprint',(select jsonb_build_object('layout',layout,'revision',layout_revision) from eshop.blueprints where id=$4)) v`,[s.order,s.payment,s.allSpots??[s.first,s.second],s.f.blueprint])).rows[0].v;
 await s.db.query('SET LOCAL ROLE authenticated');return r;
}


export async function paidAtomicSwap(t,persistent=false){
 const s=await paidSwap(t,persistent),{db,f,bindings}=s;await db.query('RESET ROLE');s.allSpots=bindings.map(b=>b.spotId);
 const source=bindings.slice(2),target=bindings.slice(0,2),unit=randomUUID();
 await db.query('update eshop.blueprint_seat_bindings set selection_unit=$2 where spot=any($1)',[source.map(b=>b.spotId),unit]);
 await db.query('update eshop.blueprints set layout=$2 where id=$1',[f.blueprint,{...s.doc,selectionUnits:[...s.doc.selectionUnits,{id:unit,kind:'atomic',nodeIds:source.map(b=>b.nodeId)}]}]);
 await db.query('update eshop.spots set product=$2 where id=any($1)',[source.map(b=>b.spotId),s.fx.product]);await db.query('update eshop.spots set product=$2 where id=any($1)',[target.map(b=>b.spotId),s.product]);
 const ticket=Number((await db.query("insert into eshop.tickets(occasion,state) values($1,'paid') returning id",[f.occasion])).rows[0].id);
 const item=Number((await db.query('insert into eshop.order_product_ticket("order",ticket,product) values($1,$2,$3) returning id',[s.order,ticket,s.fx.product])).rows[0].id);
 await db.query('update eshop.spots set order_product_ticket=$2 where id=$1',[source[1].spotId,item]);
 await db.query("update eshop.orders set price=200,data=jsonb_set(data,'{tickets}',data->'tickets'||jsonb_build_array(jsonb_build_object('id',$2::bigint,'products',jsonb_build_array(_swap_spots_generate_product_json($3,$4))))) where id=$1",[s.order,ticket,s.fx.product,source[1].spotId]);
 await db.query('update eshop.payment_info set amount=200,paid=200 where id=$1',[s.payment]);await db.query('SET LOCAL ROLE authenticated');
 return {...s,first:source[0].spotId,second:target[0].spotId,source,target};
}

