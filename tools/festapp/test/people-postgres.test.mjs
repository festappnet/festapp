import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup as formSetup,denied} from './form-fixtures.mjs';
import {peopleDescriptors,invokePeopleOperation} from '../src/operations/people.mjs';
import {MCP_PERMISSIONS,scopesForOperation} from '../../../packages/festapp_contracts/mcp-permissions.mjs';
import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';

// This suite must never succeed by silently skipping the consequential checks.
const connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
async function setup(t){
 assert(connection,'Set FESTAPP_MCP_TEST_DATABASE_URL to a supported disposable fixture');
 const {db,f}=await formSetup(t);
 await db.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));
 await db.query(await readFile(new URL('../../../supabase/migrations/20261027150000_people_group_authoring.sql',import.meta.url),'utf8'));
 await db.query('set local role authenticated');
 return {db,f};
}
async function rpc(db,f,action,payload={},command=null,unit=false){return(await db.query('select manage_people($1,$2,$3,$4,$5,$6) value',[unit?null:f.occasion,f.org,f.unit,action,payload,command])).rows[0].value;}
async function create(db,f){const r=await rpc(db,f,'profiles.create',{profile:{email:'people-'+randomUUID()+'@example.invalid',name:'Participant',note:'original'}},randomUUID());assert.equal(r.code,200,JSON.stringify(r));return r.data.profile;}
function client(db){return {rpc:async(name,args)=>{await db.query('SAVEPOINT rpc');try{const keys=Object.keys(args);const data=(await db.query('select '+name+'('+keys.map((k,i)=>k+'=> $'+(i+1)).join(',')+') value',Object.values(args))).rows[0].value;await db.query('RELEASE SAVEPOINT rpc');return{data,error:null};}catch(error){await db.query('ROLLBACK TO SAVEPOINT rpc');await db.query('RELEASE SAVEPOINT rpc');return{data:null,error};}}};}
const owner=f=>({profile:{name:'fixture',tenantId:'fixture',organizationId:f.org},root:'/tmp/people-sdk',allowedOperations:peopleDescriptors.map(d=>d.id),delegatedContext:async()=>({organizationId:f.org,unitId:f.unit}),delegatedUnitContext:async()=>({organizationId:f.org,unitId:f.unit})});

test('people scopes never expand old consent; ordinary fields reject role/metadata injection',()=>{
 assert(scopesForOperation('profiles.roles').includes('festapp:people:roles'));
 assert(!MCP_PERMISSIONS['festapp:people:write'].operations.includes('profiles.roles'));
 assert(!MCP_PERMISSIONS['festapp:unit-settings:write'].operations.includes('units.people.roles'));
 const schema=peopleDescriptors.find(d=>d.id==='profiles.save').input;
 for(const changes of [{is_manager:true},{data:{is_approver:true}},{email:'change@example.invalid'},{is_volunteer:true},{organization:2}])assert.equal(schema.safeParse({occasionId:1,userId:randomUUID(),commandId:randomUUID(),expectedVersion:0,changes}).success,false);
});
test('ordinary profile patch preserves omitted data and roles; conflict and exact frozen replay',async t=>{
 const {db,f}=await setup(t);const p=await create(db,f);const command=randomUUID();const payload={userId:p.userId,expectedVersion:p.aggregateVersion,changes:{name:'Changed'}};
 const first=await rpc(db,f,'profiles.save',payload,command);assert.equal(first.code,200,JSON.stringify(first));assert.equal(first.data.profile.profile.note,'original');assert.equal(first.data.profile.roles.is_manager,false);
 await rpc(db,f,'profiles.save',{...payload,expectedVersion:first.data.version,changes:{name:'Later'}},randomUUID());
 assert.deepEqual(await rpc(db,f,'profiles.save',payload,command),first);
 assert.equal((await rpc(db,f,'profiles.save',payload,randomUUID())).code,409);
 await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,'profiles.save',{...payload,changes:{is_manager:true}},randomUUID()],'22023');
 assert.equal((await rpc(db,f,'profiles.inspect',{userId:p.userId})).name,'Later');
});
test('explicit participant role and volunteer change uses the same version owner; manager cannot edit a foreign participant',async t=>{
 const {db,f}=await setup(t);const p=await create(db,f);
 const result=await rpc(db,f,'profiles.roles',{userId:p.userId,expectedVersion:p.aggregateVersion,changes:{is_manager:true,is_volunteer:true,is_approver:true}},randomUUID());assert.equal(result.code,200,JSON.stringify(result));assert.equal(result.data.profile.roles.is_manager,true);assert.equal(result.data.profile.roles.is_volunteer,true);
 await denied(db,'select manage_people($1,$2,$3,$4,$5,null)',[f.occasion+1,f.org,f.unit,'profiles.inspect',{userId:p.userId}]);
 const grants=(await db.query("select has_function_privilege('anon','manage_people(bigint,bigint,bigint,text,jsonb,uuid)','execute') anon,has_function_privilege('authenticated','prepare_profile_change_internal_v1(jsonb,jsonb)','execute') internal")).rows[0];assert.deepEqual(grants,{anon:false,internal:false});
});
test('self role removal is effective before replay and next read; no editor escalation',async t=>{
 const {db,f}=await setup(t);await db.query('reset role');await db.query('update unit_users set is_manager=false where unit=$1 and "user"=$2',[f.unit,f.actor]);await db.query('set local role authenticated');
 const context=async()=> (await db.query('select get_app_config_v218($1::jsonb) value',[JSON.stringify({organization:f.org,link:f.link,platform:{platform:'web'}})])).rows[0].value;
 assert.equal((await context()).capabilities['participants.write'],true);
 const before=await rpc(db,f,'profiles.inspect',{userId:f.actor});const command=randomUUID();const payload={userId:f.actor,expectedVersion:before.aggregateVersion,changes:{is_manager:false}};
 const removed=await rpc(db,f,'profiles.roles',payload,command);assert.equal(removed.code,200,JSON.stringify(removed));
 assert.equal((await context()).capabilities['participants.write'],false);
 await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,'profiles.roles',payload,command]);
 await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,'profiles.roles',{...payload,changes:{is_manager:true}},randomUUID()]);
 await denied(db,'select manage_people($1,$2,$3,$4,$5,null)',[f.occasion,f.org,f.unit,'profiles.list',{}]);
});
test('bounded profile/group pages and complete group updates share immutable versions and atomic membership',async t=>{
 const {db,f}=await setup(t);const p=await create(db,f);
 const group={title:'Team',description:'G'.repeat(9000),type:null,placeId:null,participants:[{user_id:p.userId,is_admin:false}]};
 const command=randomUUID();const first=await rpc(db,f,'groups.save',{expectedVersion:null,group},command);assert.equal(first.code,200,JSON.stringify(first));const gid=first.data.groupId;assert(gid);
 const state=await invokePeopleOperation(owner(f),client(db),'groups.inspect',{occasionId:f.occasion,groupId:gid});assert.equal(state.description.length,9000);assert.deepEqual(state.participants,group.participants);
 assert.equal((await rpc(db,f,'groups.list',{limit:1})).items.length,1);
 const added=await rpc(db,f,'groups.addMembers',{groupId:gid,userIds:[f.actor]},randomUUID());assert.equal(added.code,200,JSON.stringify(added));
 assert.deepEqual(await rpc(db,f,'groups.save',{expectedVersion:null,group},command),first);
 const conflict=await rpc(db,f,'groups.save',{groupId:gid,expectedVersion:state.aggregateVersion,group},randomUUID());assert.equal(conflict.code,409);
 const list=await rpc(db,f,'profiles.list',{limit:1});assert.equal(list.items.length,1);assert(!JSON.stringify(list).includes('original'));assert(!JSON.stringify(list).includes('email'));
});
test('group batch replacement and participant import use canonical owners and reject hidden roles',async t=>{
 const {db,f}=await setup(t);const p=await create(db,f);const command=randomUUID();const payload={assignments:[{user_id:p.userId,group_title:'Imported team'}]};
 const result=await rpc(db,f,'groups.replaceAssignments',payload,command);assert.equal(result.code,200,JSON.stringify(result));assert.deepEqual(await rpc(db,f,'groups.replaceAssignments',payload,command),result);
 const imported=await rpc(db,f,'profiles.import',{rows:[{user_id:p.userId,data:{email:(await db.query('reset role').then(()=>db.query('select email_readonly from user_info where id=$1',[p.userId]))).rows[0].email_readonly,name:'Imported'}}]},randomUUID());assert.equal(imported.code,200,JSON.stringify(imported));await db.query('set local role authenticated');
 await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,'profiles.import',{rows:[{data:{email:'x@example.invalid',is_manager:true}}]},randomUUID()],'22023');
});
test('organizer roles/profile share original version and owner; revocation blocks old receipt replay',async t=>{
 const {db,f}=await setup(t);const own=owner(f);const c=client(db);const before=await rpc(db,f,'units.list',{},null,true);assert.equal(before.items[0].aggregateVersion,0);
 const command=randomUUID();const result=await invokePeopleOperation(own,c,'units.people.profile',{unitId:f.unit,commandId:command,expectedVersion:0,userId:f.actor,changes:{name:'Organizer manager'}});assert.equal(result.aggregateVersion,1);
 assert.deepEqual(await invokePeopleOperation(own,c,'units.people.profile',{unitId:f.unit,commandId:command,expectedVersion:0,userId:f.actor,changes:{name:'Organizer manager'}}),result);
 await db.query('reset role');const headBefore=Number((await db.query("select coalesce(max(source_revision),0) n from client_sync_private_scopes where occasion=$1 and user_id=$2",[f.occasion,f.actor])).rows[0].n);await db.query('set local role authenticated');
 const roleCommand=randomUUID();const changed=await invokePeopleOperation(own,c,'units.people.roles',{unitId:f.unit,commandId:roleCommand,expectedVersion:1,userId:f.actor,changes:{is_manager:false}});assert.equal(changed.status,'applied');
 await db.query('reset role');const headAfter=Number((await db.query("select max(source_revision) n from client_sync_private_scopes where occasion=$1 and user_id=$2",[f.occasion,f.actor])).rows[0].n);assert.equal(headAfter,headBefore+1);await db.query('set local role authenticated');
 await assert.rejects(invokePeopleOperation(own,c,'units.people.profile',{unitId:f.unit,commandId:command,expectedVersion:0,userId:f.actor,changes:{name:'Organizer manager'}}),e=>e.code==='FORBIDDEN');
});
test('actual SDK lists strict tools, executes profile change through SQL and reports original-version conflict',async t=>{
 const {db,f}=await setup(t);const c=client(db);const own={...owner(f),authorized:async action=>action(c,{userId:f.actor})};
 const ops=new Operations(own),server=createServer(ops),sdk=new Client({name:'people-fixture',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await sdk.connect(b);t.after(async()=>{await sdk.close();await server.close();});
 assert.equal((await sdk.listTools()).tools.length,peopleDescriptors.length);
 const p=await create(db,f);const args={occasionId:f.occasion,userId:p.userId,expectedVersion:p.aggregateVersion,commandId:randomUUID(),changes:{note:'SDK changed'}};
 const result=await sdk.callTool({name:'festapp_profiles_save',arguments:args});assert.equal(result.structuredContent.ok,true,JSON.stringify(result));assert.equal(result.structuredContent.data.profile.profile.note,'SDK changed');
 const conflict=await sdk.callTool({name:'festapp_profiles_save',arguments:{...args,commandId:randomUUID()}});assert.equal(conflict.structuredContent.error.code,'PEOPLE_CHANGED_RELOAD_REQUIRED');
});

test('organizer creation retains confirmed identity and never overwrites an existing membership or roles',async t=>{
 const {db,f}=await setup(t);const email='organizer-'+randomUUID()+'@example.invalid';const command=randomUUID();const payload={profile:{email,name:'New member'}};
 const first=await rpc(db,f,'units.create',payload,command,true);assert.equal(first.code,200,JSON.stringify(first));assert(first.data.userId);
 assert.deepEqual(await rpc(db,f,'units.create',payload,command,true),first);
 const state=(await rpc(db,f,'units.list',{},null,true)).items.find(x=>x.userId===first.data.userId);assert.equal(state.isManager,false);assert.equal(state.aggregateVersion,1);
 const granted=await rpc(db,f,'units.roles',{userId:first.data.userId,expectedVersion:1,changes:{is_editor:true}},randomUUID(),true);assert.equal(granted.code,200,JSON.stringify(granted));
 assert.equal((await rpc(db,f,'units.create',payload,randomUUID(),true)).code,409);
 assert.equal((await rpc(db,f,'units.list',{},null,true)).items.find(x=>x.userId===first.data.userId).isEditor,true);
});
test('another ordinary identity cannot escalate, edit a foreign profile or reuse a manager command receipt',async t=>{
 const {db,f}=await setup(t);const p=await create(db,f);const command=randomUUID();const payload={userId:p.userId,expectedVersion:p.aggregateVersion,changes:{note:'Manager edit'}};await rpc(db,f,'profiles.save',payload,command);
 await db.query("select set_config('request.jwt.claim.sub',$1,true)",[p.userId]);
 for(const action of ['profiles.roles','profiles.save','profiles.inspect'])await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,action,action==='profiles.roles'?{...payload,changes:{is_manager:true}}:payload,command]);
 await denied(db,'select manage_people(null,$1,$2,$3,$4,$5)',[f.org,f.unit,'units.roles',{userId:p.userId,expectedVersion:0,changes:{is_manager:true}},randomUUID()]);
});
test('organizer access removal and participant deletion preserve canonical receipt semantics without email',async t=>{
 const {db,f}=await setup(t);const c=client(db);const own=owner(f);
 const p=await create(db,f);const before=Number((await db.query('reset role').then(()=>db.query('select count(*) n from email_messages'))).rows[0].n);await db.query('set local role authenticated');
 const removed=await invokePeopleOperation(own,c,'profiles.delete',{occasionId:f.occasion,userId:p.userId,commandId:randomUUID(),expectedVersion:p.aggregateVersion});assert.equal(removed.status,'applied');
 const command=randomUUID();const revoke=await invokePeopleOperation(own,c,'units.people.revoke',{unitId:f.unit,userId:f.actor,commandId:command});assert.equal(revoke.status,'applied');
 await assert.rejects(invokePeopleOperation(own,c,'units.people.revoke',{unitId:f.unit,userId:f.actor,commandId:command}),e=>e.code==='FORBIDDEN');
 await db.query('reset role');assert.equal(Number((await db.query('select count(*) n from email_messages')).rows[0].n),before);
});
test('ticket membership import and group deletion execute through their existing owners; invalid additive batch rolls back completely',async t=>{
 const {db,f}=await setup(t);const imported=await rpc(db,f,'profiles.importTickets',{},randomUUID());assert.equal(imported.code,200,JSON.stringify(imported));
 const group={title:'Lifecycle',description:null,type:null,placeId:null,participants:[]};const created=await rpc(db,f,'groups.save',{expectedVersion:null,group},randomUUID());const groupId=created.data.groupId;
 await denied(db,'select manage_people($1,$2,$3,$4,$5,$6)',[f.occasion,f.org,f.unit,'groups.addMembers',{groupId,userIds:[f.actor,randomUUID()]},randomUUID()],'22023');
 const state=await rpc(db,f,'groups.inspect',{groupId});assert.equal(state.participants.length,0);
 const removed=await rpc(db,f,'groups.delete',{groupId,expectedVersion:state.aggregateVersion},randomUUID());assert.equal(removed.code,200,JSON.stringify(removed));
});
test('existing canonical group/profile SQL regressions execute against final sources',async t=>{
 const {db}=await setup(t);await db.query('reset role');
 for(const file of ['groups/canonical_group_commands_test.sql','groups/add_members_test.sql','users/profile_version_fanout_test.sql','users/profile_ownership_retirement_test.sql']){
  await db.query(await readFile(new URL('../../../database/tests/'+file,import.meta.url),'utf8'));
 }
});

test('scope move and role revocation reject a blocked read or write before returning data or replay',async t=>{
 const {openDisposableDatabase}=await import('./postgres.mjs');
 const {install}=await import('./form-fixtures.mjs');
 const {fixture}=await import('../../../automation/authorization/benchmark.mjs');
 for(const scenario of ['move-read','move-write','revoke-read','revoke-replay']){
  const admin=await openDisposableDatabase(connection),changer=await openDisposableDatabase(connection),worker=await openDisposableDatabase(connection);
  try{
   await admin.query('BEGIN');await install(admin);await admin.query(await readFile(new URL('../../../supabase/migrations/20261026220000_occasion_unit_configuration.sql',import.meta.url),'utf8'));await admin.query(await readFile(new URL('../../../supabase/migrations/20261027150000_people_group_authoring.sql',import.meta.url),'utf8'));
   const f=await fixture(admin,1);const command=randomUUID();const saved=await rpc(admin,f,'profiles.save',{userId:f.actor,expectedVersion:0,changes:{note:'Original intent'}},command);assert.equal(saved.code,200,JSON.stringify(saved));
   const other=Number((await admin.query("insert into units(title,organization) values('Outside people consent',$1) returning id",[f.org])).rows[0].id);
   await admin.query('COMMIT');
   await changer.query('BEGIN');
   if(scenario.startsWith('move'))await changer.query('update occasions set unit=$1 where id=$2',[other,f.occasion]);
   else await changer.query('update occasion_users set is_manager=false,is_editor=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
   await worker.query('BEGIN');await worker.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);await worker.query('set local role authenticated');
   const writing=scenario==='move-write'||scenario==='revoke-replay';
   const pending=rpc(worker,f,writing?'profiles.save':'profiles.list',writing?{userId:f.actor,expectedVersion:scenario==='revoke-replay'?0:1,changes:{note:scenario==='revoke-replay'?'Original intent':'Must not commit'}}:{},writing?(scenario==='revoke-replay'?command:randomUUID()):null);
   const rejected=assert.rejects(pending,e=>e.code==='42501');let blocked=false;
   for(let i=0;i<50;i++){if((await admin.query('select wait_event_type from pg_stat_activity where pid=$1',[worker.processID])).rows[0]?.wait_event_type==='Lock'){blocked=true;break;}await new Promise(r=>setTimeout(r,20));}
   assert(blocked,scenario+' must wait on a real concurrent authorization/scope row');await changer.query('COMMIT');await rejected;
   assert.equal((await admin.query('select data->>\'note\' note from occasion_users where occasion=$1 and "user"=$2',[f.occasion,f.actor])).rows[0].note,'Original intent');
  }finally{for(const db of [worker,changer,admin]){await db.query('ROLLBACK');await db.end();}}
 }
});

test('bounded profile page matches the same selected UI rows with measured payload and query plan',async t=>{
 const {db,f}=await setup(t);
 await db.query('reset role');
 const prefix='people-volume-'+randomUUID();
 await db.query("select create_user_for_test($1||n,$1||n||'@example.invalid') from generate_series(1,120) n",[prefix]);
 await db.query('insert into occasion_users(occasion,"user",data) select $1,id,jsonb_build_object(\'note\',repeat(\'synthetic note \',50)) from _test_user_aliases where alias like $2',[f.occasion,prefix+'%']);
 await db.query('ANALYZE occasion_users; ANALYZE user_info; ANALYZE client_aggregate_versions');
 const plan=(await db.query(`EXPLAIN(ANALYZE,BUFFERS,FORMAT JSON) SELECT ou."user",ui.name,ui.surname,coalesce(v.version,0) FROM occasion_users ou JOIN user_info ui ON ui.id=ou."user" LEFT JOIN client_aggregate_versions v ON v.aggregate_type='occasion_user' AND v.scope_type='occasion' AND v.scope_id=$1 AND v.aggregate_id=ou."user"::text WHERE ou.occasion=$1 ORDER BY ou."user" LIMIT 50`,[f.occasion])).rows[0]['QUERY PLAN'][0];
 await db.query('set local role authenticated');
 const before=(await db.query('select get_occasion_users_editor_bundle_v1($1) value',[f.occasion])).rows[0].value;
 assert.equal(before.code,200,JSON.stringify(before));assert.equal(before.data.occasion_users.length,121);
 const after=await rpc(db,f,'profiles.list',{limit:50});
 const expected=before.data.occasion_users.map(u=>({userId:u.user,name:u.data?.name??null,surname:u.data?.surname??null,aggregateVersion:u.aggregate_version})).sort((a,b)=>a.userId.localeCompare(b.userId)).slice(0,50);
 // The old editor stores each person's resolved name in its data projection.
 assert.deepEqual(after.items,expected);
 const evidence={scenario:'Read the first 50 participant identity/version rows in UUID order',fixtureParticipants:before.data.occasion_users.length,before:{domainRequests:1,transferredParticipants:before.data.occasion_users.length,serializedBytes:Buffer.byteLength(JSON.stringify(before))},after:{domainRequests:1,transferredParticipants:after.items.length,serializedBytes:Buffer.byteLength(JSON.stringify(after))},plan,limits:'Disposable PostgreSQL with synthetic notes; local timing is not a production latency claim. Scope/Auth transport lookups excluded from both domain counts.'};
 assert(evidence.after.serializedBytes<evidence.before.serializedBytes);assert.equal(plan.Plan['Actual Rows'],50);
 t.diagnostic(`participant page bytes ${evidence.before.serializedBytes} -> ${evidence.after.serializedBytes}; identities ${evidence.before.transferredParticipants} -> 50`);
 if(process.env.FESTAPP_PEOPLE_EVIDENCE_PATH){const {writeFile}=await import('node:fs/promises');await writeFile(process.env.FESTAPP_PEOPLE_EVIDENCE_PATH,JSON.stringify(evidence,null,2)+'\n');}
});
