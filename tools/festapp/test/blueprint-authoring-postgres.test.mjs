import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup as seatSetup} from './seat-fixtures.mjs';
import {denied} from './form-fixtures.mjs';
import {invokeBlueprintOperation,blueprintDescriptors} from '../src/operations/blueprints.mjs';
import {Operations} from '../src/operations/catalog.mjs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';
import {createServer} from '../src/mcp/server.mjs';
import {scopesForOperation,MCP_PERMISSIONS} from '../../../packages/festapp_contracts/mcp-permissions.mjs';

export async function setup(t,persistent=false){
 assert(process.env.FESTAPP_MCP_TEST_DATABASE_URL,'A marker-verified disposable PostgreSQL is required');
 const state=await seatSetup(t,persistent);const {db,f}=state;await db.query('RESET ROLE');
 await db.query(await readFile(new URL('../../../supabase/migrations/20261023231000_ticket_email_delivery.sql',import.meta.url),'utf8').then(sql=>sql.replace(/^BEGIN;\s*$|^COMMIT;\s*$/gm,'')));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261027150000_people_group_authoring.sql',import.meta.url),'utf8'));
 const sql=await readFile(new URL('../../../supabase/migrations/20261027160000_blueprint_authoring.sql',import.meta.url),'utf8');await db.query(sql);
 // Production applies with postgres; match declared routine owners in this isolated TX.
 const names=[...sql.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)\s*\(/g)].map(m=>m[1]);
 for(const row of (await db.query("select format('ALTER FUNCTION %s OWNER TO postgres',oid::regprocedure) command from pg_proc where pronamespace='public'::regnamespace and proname=any($1)",[names])).rows)await db.query(row.command);
 await db.query('SET LOCAL ROLE authenticated');
 const client={rpc:async(name,args)=>{await db.query('SAVEPOINT rpc');try{const keys=Object.keys(args);const data=(await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value',Object.values(args))).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');return{data,error:null};}catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error};}}};
 const owner={...state.ex.owner,allowedOperations:blueprintDescriptors.map(d=>d.id),authorized:action=>action(client,{userId:f.actor})};
 return {...state,client,owner};
}
function draft(state,changes={}){return{occasionId:state.occasionId,blueprintId:state.blueprintId,expectedLayoutRevision:state.layoutRevision,title:state.title,layout:state.layout,textResourceIds:state.textResourceIds,seatChanges:[],groupProductChanges:[],areaBindingChanges:[],...changes,commandId:randomUUID()};}
const inspect=(s)=>invokeBlueprintOperation(s.owner,s.client,'blueprints.inspect',{occasionId:s.f.occasion,blueprintId:s.f.blueprint});

test('blueprint/appearance scopes are new, bounded and cannot expand old consent',()=>{
 assert(scopesForOperation('ticket_layouts.save').includes('festapp:ticket-artwork:write'));
 assert(scopesForOperation('blueprints.save').includes('festapp:blueprints:write'));
 assert(!MCP_PERMISSIONS['festapp:occasion-settings:write'].operations.includes('blueprints.save'));
 const schema=blueprintDescriptors.find(d=>d.id==='blueprints.save').input;
 assert.equal(schema.safeParse({occasionId:1,commandId:randomUUID(),data:{arbitrary:true}}).success,false);
});
test('blueprint exact draft save, geometry/naming, original revision and frozen replay use the existing owner',async t=>{
 const s=await setup(t);const before=await inspect(s);const changed=structuredClone(before.layout);changed.canvas.width+=100;
 const request=draft(before,{layout:changed,title:'Approved draft'});const result=await invokeBlueprintOperation(s.owner,s.client,'blueprints.save',request);assert.equal(result.layoutRevision,before.layoutRevision+1);
 assert.deepEqual((await inspect(s)).layout,changed);
 assert.deepEqual(await invokeBlueprintOperation(s.owner,s.client,'blueprints.save',request),result);
 await assert.rejects(invokeBlueprintOperation(s.owner,s.client,'blueprints.save',{...request,commandId:randomUUID()}),e=>e.code==='BLUEPRINT_CHANGED_RELOAD_REQUIRED');
 const after=await inspect(s);assert.equal(after.title,'Approved draft');assert.deepEqual(after.seatBindings,before.seatBindings);
});
test('advisory validation and discarded draft perform no save, and protected seat deletion rolls back',async t=>{
 const s=await setup(t);const before=await inspect(s);const candidate=structuredClone(before.layout);candidate.canvas.width+=20;
 assert.equal((await invokeBlueprintOperation(s.owner,s.client,'blueprints.validate',{occasionId:s.f.occasion,layout:candidate})).valid,true);assert.deepEqual(await inspect(s),before);
 await s.db.query('RESET ROLE');await s.db.query("update eshop.spots set secret=$1,secret_expiration_time=now()+interval '5 minutes' where id=$2",[randomUUID(),s.bindings[0].spotId]);await s.db.query('SET LOCAL ROLE authenticated');
 const layout=structuredClone(before.layout);layout.nodes=layout.nodes.filter(n=>n.id!==s.bindings[0].nodeId);layout.selectionUnits=[];
 await assert.rejects(invokeBlueprintOperation(s.owner,s.client,'blueprints.save',draft(before,{layout,seatChanges:[{nodeId:s.bindings[0].nodeId,operation:'delete'}]})),e=>e.code==='BLUEPRINT_DRAFT_REJECTED');
 assert.deepEqual(await inspect(s),before);
});
test('stored scope and ordinary role revoke reads and replay; private resource functions have no public grant',async t=>{
 const s=await setup(t);const state=await inspect(s);const request=draft(state);await invokeBlueprintOperation(s.owner,s.client,'blueprints.save',request);
 await denied(s.db,'select manage_blueprint_authoring($1,$2,$3,$4,$5,null)',[s.f.occasion,s.f.org+1,s.f.unit,'inspect',{blueprintId:s.f.blueprint}]);
 await s.db.query('RESET ROLE');await s.db.query('update occasion_users set is_editor=false,is_manager=false where occasion=$1 and "user"=$2',[s.f.occasion,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 await assert.rejects(inspect(s),e=>e.code==='FORBIDDEN');await assert.rejects(invokeBlueprintOperation(s.owner,s.client,'blueprints.save',request),e=>e.code==='FORBIDDEN');
 const a=(await s.db.query("select has_function_privilege('authenticated','register_delegated_blueprint_text_resources(bigint,bigint,bigint,uuid,jsonb)','execute') service_boundary,has_function_privilege('anon','manage_blueprint_authoring(bigint,bigint,bigint,text,jsonb,uuid)','execute') anonymous")).rows[0];assert.deepEqual(a,{service_boundary:false,anonymous:false});
});
test('actual SDK executes scoped blueprint draft and current runtime artwork contract remains ready',async t=>{
 const s=await setup(t);const ops=new Operations(s.owner);const server=createServer(ops),sdk=new Client({name:'blueprint-fixture',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await sdk.connect(b);t.after(async()=>{await sdk.close();await server.close();});
 const result=await sdk.callTool({name:'festapp_blueprints_inspect',arguments:{occasionId:s.f.occasion,blueprintId:s.f.blueprint}});assert.equal(result.structuredContent.ok,true,JSON.stringify(result));
 const saved=await sdk.callTool({name:'festapp_blueprints_save',arguments:draft(result.structuredContent.data)});assert.equal(saved.structuredContent.ok,true,JSON.stringify(saved));
 const contract=(await s.db.query('select get_ticket_layout_write_contract_v1() value')).rows[0].value;
 if(!contract.ready){const contractSql=await readFile(new URL('../../../database/functions/others/get_ticket_layout_write_contract_v1.sql',import.meta.url),'utf8');const values=contractSql.split('INTO ready FROM (VALUES')[1].split(') expected(signature,body_md5,definer,needs_path)')[0];const mismatch=(await s.db.query("select expected.signature,md5(btrim(p.prosrc,E' \\n\\r\\t')) actual,expected.body_md5 expected from (values "+values+") expected(signature,body_md5,definer,needs_path) left join pg_proc p on p.oid=to_regprocedure(expected.signature) where p.oid is null or md5(btrim(p.prosrc,E' \\n\\r\\t'))<>expected.body_md5")).rows;t.diagnostic(JSON.stringify(mismatch));}
 assert.equal(contract.ready,true,JSON.stringify(contract));
});

test('delegated immutable text resources fence real actor permission and stored organization in SQL',async t=>{
 const s=await setup(t);const families=await invokeBlueprintOperation(s.owner,s.client,'blueprints.fonts',{occasionId:s.f.occasion,limit:5});assert.equal(families.families.length,5);
 const resources=(await s.db.query('RESET ROLE').then(()=>s.db.query('select blueprint_test_number_resources_internal() value'))).rows[0].value;
 await s.db.query("select set_config('request.jwt.claim.sub','',true),set_config('request.jwt.claim.role','service_role',true)");
 await s.db.query('select register_delegated_blueprint_text_resources($1,$2,$3,$4,$5)',[s.f.occasion,s.f.org,s.f.unit,s.f.actor,resources]);
 await denied(s.db,'select register_delegated_blueprint_text_resources($1,$2,$3,$4,$5)',[s.f.occasion,s.f.org+1,s.f.unit,s.f.actor,resources]);
 await s.db.query('update occasion_users set is_editor=false,is_manager=false where occasion=$1 and "user"=$2',[s.f.occasion,s.f.actor]);
 await denied(s.db,'select register_delegated_blueprint_text_resources($1,$2,$3,$4,$5)',[s.f.occasion,s.f.org,s.f.unit,s.f.actor,resources]);
});
test('full draft save waits for a real checkout hold then rejects protected binding changes and geometry together',async t=>{
 const s=await setup(t,true);const before=await inspect(s);const {openDisposableDatabase}=await import('./postgres.mjs');const buyer=await openDisposableDatabase(process.env.FESTAPP_MCP_TEST_DATABASE_URL);t.after(async()=>{await buyer.query('ROLLBACK');await buyer.end();});
 const layout=structuredClone(before.layout);layout.canvas.width+=100;
 const request=draft(before,{layout,seatChanges:before.seatBindings.slice(0,2).map(b=>({...b,operation:'upsert',blocked:true}))});
 await s.db.query('COMMIT');await buyer.query('BEGIN');
 const held=(await buyer.query('select select_spot($1,$2,$3,true) value',[s.fx.formKey,randomUUID(),s.bindings[0].spotId])).rows[0].value;assert.equal(held.code,200,JSON.stringify(held));
 await s.db.query('BEGIN');await s.db.query("set local statement_timeout='5s'");await s.db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 const pending=invokeBlueprintOperation(s.owner,s.client,'blueprints.save',request);const rejected=assert.rejects(pending,e=>e.code==='BLUEPRINT_DRAFT_REJECTED');
 let blocked=false;for(let i=0;i<100;i++){if((await buyer.query('select $1::int=any(pg_blocking_pids($2)) blocked',[buyer.processID,s.db.processID])).rows[0].blocked){blocked=true;break;}await new Promise(r=>setTimeout(r,10));}
 assert(blocked,'full draft must wait for the actual canonical checkout transaction');await buyer.query('COMMIT');await rejected;
 const after=await inspect(s);assert.equal(after.layoutRevision,before.layoutRevision);assert.deepEqual(after.layout,before.layout);assert(after.seatBindings.every(b=>!b.blocked));
});
test('scanner adapter reuses real eligibility, session and operation owners without leaking credentials or duplicating admission',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');
 for(const name of ['20261019030000_web_scanner.sql','20261019040000_scanner_settings_editors.sql','20261019050000_scanner_form_field_catalog.sql','20261024234000_scanner_batch_identity.sql','20261026020000_scanner_auto_offline_summary.sql']){
  const sql=(await readFile(new URL('../../../supabase/migrations/'+name,import.meta.url),'utf8')).replace(/^BEGIN;\s*$|^COMMIT;\s*$/gm,'');await s.db.query(sql);
 }
 await s.db.query(await readFile(new URL('../../../database/tests/scanning/fixture.sql',import.meta.url),'utf8'));
 const fixture=(await s.db.query('select scanner_test_fixture(1) value')).rows[0].value;const oc=Number(fixture.occasion);const ticketId=Number(fixture.tickets[0]);
 const resource=(await s.db.query('select organization,unit from occasions where id=$1',[oc])).rows[0];
 await s.db.query('insert into occasion_users(occasion,"user",is_editor,is_editor_order) values($1,$2,true,true)',[oc,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 const {invokeScannerOperation}=await import('../src/operations/scanner.mjs');const owner={delegatedContext:async()=>({organizationId:Number(resource.organization),unitId:Number(resource.unit)})};
 const before=await invokeScannerOperation(owner,s.client,'scanner.inspect',{occasionId:oc,ticketId});assert.equal(before.admissionAllowed,true);
 const request={occasionId:oc,ticketId,operationId:randomUUID(),eligibilityFingerprint:before.eligibilityFingerprint,settingsRevision:before.settingsRevision,confirmUnpaid:false,capturedAt:new Date().toISOString()};
 const admitted=await invokeScannerOperation(owner,s.client,'scanner.admit',request);assert.equal(admitted.outcome,'accepted',JSON.stringify(admitted));
 const replay=await invokeScannerOperation(owner,s.client,'scanner.admit',request);assert.equal(replay.replayed,true);assert.equal(replay.committedAt,admitted.committedAt);
 assert.equal((await invokeScannerOperation(owner,s.client,'scanner.inspect',{occasionId:oc,ticketId})).state,'used');
 assert(!JSON.stringify(admitted).includes('token'));assert(!JSON.stringify(admitted).includes('symbol'));
 await assert.rejects(invokeScannerOperation(owner,s.client,'scanner.admit',{...request,confirmUnpaid:true}),e=>e.code==='SCANNER_INTENT_REJECTED');
});
