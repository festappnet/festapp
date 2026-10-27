import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';
import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup as formSetup,options,denied} from './form-fixtures.mjs';
import {configurationDescriptors,invokeConfigurationOperation} from '../src/operations/configuration.mjs';
import {MCP_PERMISSIONS,scopesForOperation} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
async function setup(t){const {db,f}=await formSetup(t);await db.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));return {db,f};}
async function read(db,f,kind='occasion'){return(await db.query('select get_configuration_settings($1,$2,$3,$4) value',[kind,kind==='unit'?f.unit:f.occasion,f.org,f.unit])).rows[0].value;}
async function save(db,f,changes,version=0,command=randomUUID(),kind='occasion'){return(await db.query('select save_configuration_settings($1,$2,$3,$4,$5,$6,$7) value',[kind,kind==='unit'?f.unit:f.occasion,f.org,f.unit,version,command,changes])).rows[0].value;}
function client(db){return {rpc:async(name,args)=>{const keys=Object.keys(args);try{return{data:(await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value',Object.values(args))).rows[0].value,error:null};}catch(error){return{data:null,error};}}};}
function owner(f){return{delegatedContext:async()=>({organizationId:f.org,unitId:null}),delegatedUnitContext:async()=>({organizationId:f.org,unitId:f.unit})};}

test('configuration scopes are explicit, preserve old consents and reject arbitrary paths',()=>{
 assert.deepEqual(scopesForOperation('units.settings.save'),['festapp:unit-settings:read','festapp:unit-settings:write']);
 assert(!MCP_PERMISSIONS['festapp:forms:write'].operations.includes('occasions.settings.save'));
 const schema=configurationDescriptors.find(d=>d.id==='occasions.settings.save').input;
 for(const changes of [{data:{client_sync_v1:false}},{organization:2},{unit:2},{settings:{game:{start:null}}},{feature_changes:[{code:'ticket',layout:{}}]},{feature_changes:[{code:'stripe',is_enabled:true}]},{feature_changes:[{code:'map',defaultMapLocation:{lat:49}}]}])
  assert.equal(schema.safeParse({occasionId:1,commandId:randomUUID(),expectedVersion:0,changes}).success,false);
});
test('occasion patch preserves opaque data, features and instants; read/receipt projection and frozen replay agree',options,async t=>{
 const {db,f}=await setup(t);await db.query("update occasions set data='{\"timezone\":\"Europe/Prague\",\"opaque_owner_data\":{\"keep\":true},\"game\":{\"start\":null}}',features='[{\"code\":\"ticket\",\"is_enabled\":true,\"delivery_mode\":\"pdf_attachment\",\"private_owner\":true}]' where id=$1",[f.occasion]);
 const before=await read(db,f);assert(!JSON.stringify(before).includes('opaque_owner_data'));assert(!JSON.stringify(before).includes('private_owner'));assert(!('link'in before));
 const intent={title:'Updated occasion',settings:{timezone:'America/New_York',reply_to:'organizer@example.invalid'},feature_changes:[{code:'ticket',can_scan_manually:true,show_hidden_note:true}]};
 const command=randomUUID();const first=await save(db,f,intent,0,command);assert.equal(first.code,200,JSON.stringify(first));
 const state=first.data.configuration;assert.equal(state.aggregateVersion,1);assert.equal(state.startTime,before.startTime);assert.equal(state.endTime,before.endTime);assert.deepEqual(await read(db,f),state);
 const raw=(await db.query('select data,features from occasions where id=$1',[f.occasion])).rows[0];assert.equal(raw.data.opaque_owner_data.keep,true);assert.equal(raw.features[0].private_owner,true);assert.equal(raw.features[0].delivery_mode,'pdf_attachment');
 await save(db,f,{title:'Later edit'},1);
 const replay=await save(db,f,intent,0,command);assert.deepEqual(replay.data,first.data);assert.deepEqual(replay,first);
 const stale=await save(db,f,{title:'Stale'},0);assert.equal(stale.code,409);assert.equal(stale.data.configuration.title,'Later edit');
 await denied(db,'select save_configuration_settings($1,$2,$3,$4,$5,$6,$7)',['occasion',f.occasion,f.org,f.unit,0,command,{title:'Different intent'}],'22023');
});
test('shared occasion owner validates time, timezone, feature prerequisites and protected fields',options,async t=>{
 const {db,f}=await setup(t);
 for(const changes of [
  {settings:{timezone:'Invalid/Zone'}},{settings:{reply_to:'bad address'}},{settings:{image:'https://example.invalid/foreign.png'}},
  {start_time:'2030-01-03T00:00:00Z',end_time:'2030-01-01T00:00:00Z'},
  {feature_changes:[{code:'game',is_enabled:true}]},{feature_changes:[{code:'program_notifications',is_enabled:true}]},
  {feature_changes:[{code:'form',is_enabled:false}]},{feature_changes:[{code:'ticket',layout:{}}]},
  {feature_changes:[{code:'ticket',can_scan_manually:'yes'}]},
  {feature_changes:[{code:'ticket'},{code:'ticket'}]},
  {settings:{client_sync_v1:true}},{is_promoted:true},{unit:f.unit+1},{organization:f.org+1},{data:{}},
 ])await denied(db,'select save_configuration_settings($1,$2,$3,$4,$5,$6,$7)',['occasion',f.occasion,f.org,f.unit,0,randomUUID(),changes],'22023');
 // A legacy direct save reaches the same validator, rather than bypassing prerequisites.
 await denied(db,'select save_occasion_client_sync_v1($1,$2,0,$3)',[f.occasion,randomUUID(),{id:f.occasion,features:[{code:'game',is_enabled:true}]}],'22023');
 await db.query("update organizations set data=data||'{\"IS_APP_SUPPORTED\":true}' where id=$1",[f.org]);
 await denied(db,'select save_configuration_settings($1,$2,$3,$4,0,$5,$6)',['occasion',f.occasion,f.org,f.unit,randomUUID(),{feature_changes:[{code:'map',is_enabled:true,map_layer_offline:{forceOfflineMap:true}}]}],'22023');
 const result=await save(db,f,{feature_changes:[{code:'game',is_enabled:true},{code:'companions',is_enabled:true,max_companions:2,allow_admin_assign:true},{code:'map',is_enabled:true,defaultMapLocation:{lat:49,lng:17},map_layer_offline:{forceOfflineMap:true,offlineMapBundleManifestURL:'https://img.festapp.net/assets/map-bundle.json'}}]});assert.equal(result.code,200,JSON.stringify(result));
});
test('unit settings share owner, preserve metadata, reset inheritance and reject original-version conflicts',options,async t=>{
 const {db,f}=await setup(t);await db.query("update units set data='{\"opaque_owner\":true,\"reply_to\":\"old@example.invalid\"}' where id=$1",[f.unit]);
 const original=await read(db,f,'unit');assert(!('opaque_owner'in original.settings));
 const command=randomUUID();const intent={title:'Organizer',settings:{reply_to:null,communication_tone:'informal',timezone:'Europe/Prague'}};
 const first=await save(db,f,intent,0,command,'unit');assert.equal(first.code,200,JSON.stringify(first));assert.equal(first.data.configuration.aggregateVersion,1);assert(!('reply_to'in first.data.configuration.settings));assert.deepEqual(first.data.configuration,await read(db,f,'unit'));
 assert.equal((await db.query('select data from units where id=$1',[f.unit])).rows[0].data.opaque_owner,true);
 await save(db,f,{title:'Later organizer'},1,randomUUID(),'unit');assert.deepEqual((await save(db,f,intent,0,command,'unit')).data,first.data);
 assert.equal((await save(db,f,{title:'Stale'},0,randomUUID(),'unit')).code,409);
 for(const changes of [{title:''},{title:'x'.repeat(31)},{settings:{communication_tone:'casual'}},{settings:{timezone:'bad'}}])await denied(db,'select save_configuration_settings($1,$2,$3,$4,2,$5,$6)',['unit',f.unit,f.org,f.unit,randomUUID(),changes],'22023');
});
test('real authenticated roles, tenant binding, scope changes and replay revocation',options,async t=>{
 const {db,f}=await setup(t);const command=randomUUID();await save(db,f,{title:'Authorized'},0,command);
 const moved=Number((await db.query("insert into units(title,organization) values('Other organizer',$1) returning id",[f.org])).rows[0].id);
 await db.query('update unit_users set is_manager=false,is_editor=false,is_editor_view=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await db.query('set local role authenticated');
 // Occasion editor grant survives; it does not authorize the unit manager operation or config save.
 await denied(db,'select get_configuration_settings($1,$2,$3,$4)',['unit',f.unit,f.org,f.unit]);
 await denied(db,'select save_configuration_settings($1,$2,$3,$4,0,$5,$6)',['unit',f.unit,f.org,f.unit,randomUUID(),{title:'Escalated'}]);
 await denied(db,'select save_configuration_settings($1,$2,$3,$4,0,$5,$6)',['occasion',f.occasion,f.org,f.unit,command,{title:'Authorized'}]);
 await denied(db,'select get_configuration_settings($1,$2,$3,$4)',['occasion',f.occasion,f.org+1,f.unit]);
 await db.query('reset role');await db.query('update occasions set unit=$1 where id=$2',[moved,f.occasion]);await db.query('set local role authenticated');
 await denied(db,'select get_configuration_settings($1,$2,$3,$4)',['occasion',f.occasion,f.org,f.unit]);
 await denied(db,'select save_occasion_client_sync_v1($1,$2,0,$3)',[f.occasion,randomUUID(),{id:f.occasion,unit:f.unit}]);
});
test('public link uses allocator/history, preserves omitted features/data and freezes replay link',options,async t=>{
 const {db,f}=await setup(t);const slug='stage5-'+randomUUID();const command=randomUUID();const args=[f.occasion,f.org,f.unit,command,0,slug];
 const first=(await db.query('select manage_occasion_public_link($1,$2,$3,$4,$5,$6) value',args)).rows[0].value;assert.equal(first.code,200,JSON.stringify(first));assert.equal(first.data.link,slug);
 assert.equal(Number((await db.query('select resolve_occasion_link_internal($1) id',[f.link])).rows[0].id),f.occasion);
 await save(db,f,{title:'After link edit'},1);
 assert.deepEqual((await db.query('select manage_occasion_public_link($1,$2,$3,$4,$5,$6) value',args)).rows[0].value.data,first.data);
});
test('game uses original version, same receipt owner, real game role and valid interval',options,async t=>{
 const {db,f}=await setup(t);const cmd=randomUUID();const args=[f.occasion,'2030-01-01T10:00:00Z','2030-01-01T11:00:00Z',cmd,0];
 const result=(await db.query('select game_update_settings_client_sync_v1($1,$2,$3,$4,$5) value',args)).rows[0].value;assert.equal(result.code,200,JSON.stringify(result));assert.equal(result.data.version,1);
 const conflict=(await db.query('select game_update_settings_client_sync_v1($1,null,null,$2,0) value',[f.occasion,randomUUID()])).rows[0].value;assert.equal(conflict.code,409);
 await denied(db,'select game_update_settings_client_sync_v1($1,$2,$3,$4,1)',[f.occasion,'2030-01-03T00:00Z','2030-01-01T00:00Z',randomUUID()],'22023');
 await db.query('update unit_users set is_manager=false,is_editor=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('set local role authenticated');
 const state=(await db.query('select get_game_settings_for_authoring_v1($1) value',[f.occasion])).rows[0].value;assert.deepEqual(state.game,result.data.game);
 const replay=(await db.query('select game_update_settings_client_sync_v1($1,$2,$3,$4,$5) value',args)).rows[0].value;assert.deepEqual(replay.data,result.data);
 await db.query('reset role');await db.query('update occasion_users set is_editor=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);await db.query('set local role authenticated');
 await denied(db,'select game_update_settings_client_sync_v1($1,$2,$3,$4,$5)',args);
});
test('MCP executor consumes real owner snapshots and explicit whole-unit delegation',options,async t=>{
 const {db,f}=await setup(t);const own=owner(f),c=client(db);
 const inspected=await invokeConfigurationOperation(own,c,'occasions.settings.inspect',{occasionId:f.occasion});assert.equal(inspected.aggregateVersion,0);
 const saved=await invokeConfigurationOperation(own,c,'occasions.settings.save',{occasionId:f.occasion,commandId:randomUUID(),expectedVersion:0,changes:{title:'From MCP',settings:{reply_to:null}}});assert.equal(saved.title,'From MCP');
 const unit=await invokeConfigurationOperation(own,c,'units.settings.inspect',{unitId:f.unit});assert.equal(unit.entityId,f.unit);
 await assert.rejects(invokeConfigurationOperation({...own,delegatedUnitContext:async()=>{throw new Error('whole unit consent required');}},c,'units.settings.save',{unitId:f.unit,expectedVersion:0,commandId:randomUUID(),changes:{title:'Forbidden'}}),/whole unit consent required/);
 const game=await invokeConfigurationOperation(own,c,'occasions.game.inspect',{occasionId:f.occasion});assert.equal(game.aggregateVersion,1);
 const gameSaved=await invokeConfigurationOperation(own,c,'occasions.game.save',{occasionId:f.occasion,commandId:randomUUID(),expectedVersion:1,start:null,end:null});assert.equal(gameSaved.status,'applied');
});

test('SDK lists all eight configuration tools and executes real versioned save snapshots',options,async t=>{
 const {db,f}=await setup(t),c=client(db);
 const own={...owner(f),root:'/tmp/stage5-sdk',profile:{name:'fixture',tenantId:'fixture',organizationId:f.org,backendOrigin:'http://127.0.0.1:55432'},allowedOperations:configurationDescriptors.map(d=>d.id),authorized:async action=>action(c,{userId:f.actor})};
 const ops=new Operations(own),server=createServer(ops),sdk=new Client({name:'stage5-fixture',version:'1'});
 const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await sdk.connect(b);t.after(async()=>{await sdk.close();await server.close();});
 assert.equal((await db.query('select get_ticket_layout_write_contract_v1() value')).rows[0].value.ready,true,'settings owner changes must retain the ticket-layout write contract');
 const tools=await sdk.listTools();assert.equal(tools.tools.length,8);
 const inspect=await sdk.callTool({name:'festapp_occasions_settings_inspect',arguments:{occasionId:f.occasion}});assert.equal(inspect.structuredContent.ok,true,JSON.stringify(inspect));
 const result=await sdk.callTool({name:'festapp_occasions_settings_save',arguments:{occasionId:f.occasion,commandId:randomUUID(),expectedVersion:inspect.structuredContent.data.aggregateVersion,changes:{title:'SDK occasion'}}});
 assert.equal(result.structuredContent.ok,true,JSON.stringify(result));assert.equal(result.structuredContent.data.title,'SDK occasion');
 const conflict=await sdk.callTool({name:'festapp_occasions_settings_save',arguments:{occasionId:f.occasion,commandId:randomUUID(),expectedVersion:0,changes:{title:'Stale SDK edit'}}});assert.equal(conflict.structuredContent.error.code,'CONFIGURATION_CHANGED_RELOAD_REQUIRED');
 const grants=(await db.query("select has_function_privilege('authenticated','public.apply_occasion_settings_intent_internal_v1(bigint,jsonb)','EXECUTE') internal,has_function_privilege('anon','public.save_configuration_settings(text,bigint,bigint,bigint,bigint,uuid,jsonb)','EXECUTE') anonymous")).rows[0];assert.deepEqual(grants,{internal:false,anonymous:false});
});

test('concurrent move outside organizer consent rejects reads and rolls back a versioned write after its row lock',options,async t=>{
 const {openDisposableDatabase}=await import('./postgres.mjs');
 const {connection,install}=await import('./form-fixtures.mjs');
 const {fixture}=await import('../../../automation/authorization/benchmark.mjs');
 for(const operation of ['read','write']){
  const admin=await openDisposableDatabase(connection),mover=await openDisposableDatabase(connection),worker=await openDisposableDatabase(connection);
  try{
   await admin.query('BEGIN');await install(admin);await admin.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));
   const f=await fixture(admin,1);const other=Number((await admin.query("insert into units(title,organization) values('Outside stage5 consent',$1) returning id",[f.org])).rows[0].id);
   await admin.query('insert into unit_users(unit,"user",is_editor,is_manager,is_editor_view) values($1,$2,true,true,true)',[other,f.actor]);await admin.query('COMMIT');
   await mover.query('BEGIN');await mover.query('update occasions set unit=$1 where id=$2',[other,f.occasion]);
   await worker.query('BEGIN');await worker.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true),set_config('festapp.email_wake','scheduled',true)",[f.actor]);await worker.query('set local role authenticated');
   const command=randomUUID();const pending=operation==='read'?worker.query("select get_configuration_settings('occasion',$1,$2,$3)",[f.occasion,f.org,f.unit]):worker.query("select save_configuration_settings('occasion',$1,$2,$3,0,$4,$5)",[f.occasion,f.org,f.unit,command,{title:'Must roll back outside consent'}]);
   const rejected=assert.rejects(pending,e=>e.code==='42501');let blocked=false;
   for(let i=0;i<50;i++){if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[worker.processID])).rows[0]?.wait_event_type==='Lock'){blocked=true;break;}await new Promise(r=>setTimeout(r,20));}
   assert(blocked,operation+' must wait on the actual concurrently moved row');await mover.query('COMMIT');await rejected;
   assert.equal((await admin.query('select title from occasions where id=$1',[f.occasion])).rows[0].title,'Authz 1');
   assert.equal(Number((await admin.query("select count(*) n from client_aggregate_versions where aggregate_type='occasion' and scope_id=$1",[f.occasion])).rows[0].n),0);
  }finally{for(const db of [worker,mover,admin]){await db.query('ROLLBACK');await db.end();}}
 }
});
