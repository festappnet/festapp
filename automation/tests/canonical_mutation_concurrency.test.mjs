import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomUUID } from 'node:crypto';
const require = createRequire(new URL('../../web_client/package.json', import.meta.url));
const { Client } = require('pg');
const target = process.env.DATABASE_URL;
function requireDisposable() {
  const u = new URL(target ?? 'http://missing');
  assert.equal(u.hostname, '127.0.0.1');
  assert.equal(u.port, '55452');
  assert.equal(u.pathname, '/postgres');
  assert.equal(process.env.FESTAPP_DISPOSABLE_PROJECT, 'festapp-canonical-mutation-pg15');
}
async function blockedBy(a, bPid, aPid) {
  const deadline = Date.now() + 5000;
  while (Date.now() < deadline) {
    const { rows } = await a.query('SELECT $1::int=ANY(pg_blocking_pids($2::int)) blocked', [aPid,bPid]);
    if (rows[0].blocked) return;
    await new Promise(resolve => setTimeout(resolve, 10));
  }
  assert.fail('Second connection never reached the expected lock barrier');
}
test('two group editors serialize, loser conflicts; private move shares group clock', async () => {
  requireDisposable();
  const a = new Client({ connectionString: target });
  const b = new Client({ connectionString: target });
  let occasion;
  await a.connect(); await b.connect();
  try {
    assert.equal((await a.query("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton")).rows[0].project,'festapp-canonical-mutation-pg15');
    await a.query("SET statement_timeout='10s'"); await b.query("SET statement_timeout='10s'");
    const { rows: [identity] } = await a.query("SELECT (SELECT id FROM auth.users ORDER BY created_at LIMIT 1) actor,id unit,organization FROM public.units LIMIT 1");
    assert.ok(identity.actor, 'disposable seeded identity');
    const { rows: [scope] } = await a.query("INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open) VALUES($1,$2,'Concurrency group',$3,now(),now()+interval '1 day',true) RETURNING id",[identity.organization,identity.unit,randomUUID()]);
    occasion = scope.id;
    await a.query('INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_approved) VALUES($1,$2,true,true,true)',[occasion,identity.actor]);
    await a.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[identity.actor]);
    await b.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[identity.actor]);
    const create = { title:'Team', participants:[],privatePlace:{title:'Private',coordinates:{latLng:{lat:50,lng:14}}} };
    const { rows: [created] } = await a.query('SELECT public.save_user_group_client_sync_v1($1,$2,NULL,$3::jsonb) result',[occasion,randomUUID(),JSON.stringify(create)]);
    const group = created.result.data.group;
    const dto = {...create,id:group.id,privatePlace:{...create.privatePlace,id:group.place}};
    const aPid = (await a.query('SELECT pg_backend_pid() pid')).rows[0].pid;
    const bPid = (await b.query('SELECT pg_backend_pid() pid')).rows[0].pid;
    await a.query('BEGIN');
    const first = await a.query('SELECT public.save_user_group_client_sync_v1($1,$2,1,$3::jsonb) result',[occasion,randomUUID(),JSON.stringify({...dto,title:'Winner'})]);
    const waiting = b.query('SELECT public.save_user_group_client_sync_v1($1,$2,1,$3::jsonb) result',[occasion,randomUUID(),JSON.stringify({...dto,title:'Loser'})]);
    await blockedBy(a,bPid,aPid);
    await a.query('COMMIT');
    assert.equal(first.rows[0].result.status,'applied');
    assert.equal((await waiting).rows[0].result.status,'conflict');
    await a.query('BEGIN');
    await a.query('SELECT public.move_place_client_sync_v1($1,$2,$3,1,51,15)',[occasion,group.place,randomUUID()]);
    const stale = b.query('SELECT public.save_user_group_client_sync_v1($1,$2,2,$3::jsonb) result',[occasion,randomUUID(),JSON.stringify({...dto,title:'Stale coordinates'})]);
    await blockedBy(a,bPid,aPid);
    await a.query('COMMIT');
    assert.equal((await stale).rows[0].result.status,'conflict');
    assert.equal((await a.query('SELECT coordinates FROM public.places WHERE id=$1',[group.place])).rows[0].coordinates.latLng.lat,51);
  } catch (error) {
    console.error(error);
    throw error;
  } finally {
    try {
    await a.query('ROLLBACK'); await b.query('ROLLBACK');
    if (occasion) {
      await a.query('DELETE FROM public.user_groups WHERE "group" IN (SELECT id FROM public.user_group_info WHERE occasion=$1)',[occasion]);
      await a.query('DELETE FROM public.user_group_info WHERE occasion=$1',[occasion]);
      await a.query('DELETE FROM public.places WHERE occasion=$1',[occasion]);
      await a.query('DELETE FROM public.client_mutation_receipts WHERE occasion=$1',[occasion]);
      for (const relation of ['client_commit_items','client_commit_components']) await a.query(`DELETE FROM public.${relation} WHERE commit_id IN (SELECT commit_id FROM public.client_commits WHERE occasion=$1)`,[occasion]);
      await a.query('DELETE FROM public.client_commits WHERE occasion=$1',[occasion]);
      await a.query('DELETE FROM public.client_aggregate_versions WHERE scope_type=\'occasion\' AND scope_id=$1',[occasion]);
      await a.query('DELETE FROM public.client_sync_private_scopes WHERE occasion=$1',[occasion]);
      await a.query('DELETE FROM public.occasion_users WHERE occasion=$1',[occasion]);
      await a.query('DELETE FROM public.occasions WHERE id=$1',[occasion]);
    }
    } finally { await a.end(); await b.end(); }
  }
});

async function withActivityEditors(run) {
  requireDisposable();
  const a=new Client({connectionString:target}),b=new Client({connectionString:target});
  await a.connect();await b.connect();
  assert.equal((await a.query("SELECT project FROM festapp_test_support.disposable_environment WHERE singleton")).rows[0].project,'festapp-canonical-mutation-pg15');
  const scopes=[];
  try {
    await a.query("SET statement_timeout='10s'");await b.query("SET statement_timeout='10s'");
    const identity=(await a.query('SELECT (SELECT id FROM auth.users ORDER BY created_at LIMIT 1) actor,id unit,organization FROM public.units LIMIT 1')).rows[0];
    for (let i=0;i<2;i++) {
      const o=(await a.query("INSERT INTO public.occasions(organization,unit,title,link,start_time,end_time,is_open) VALUES($1,$2,'Activity concurrency',$3,now(),now()+interval '1 day',true) RETURNING id",[identity.organization,identity.unit,randomUUID()])).rows[0].id;
      scopes.push(o);await a.query('INSERT INTO public.occasion_users(occasion,"user",is_editor,is_editor_view,is_approved) VALUES($1,$2,true,true,true)',[o,identity.actor]);
    }
    for (const c of [a,b]) await c.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[identity.actor]);
    await run(a,b,scopes,identity.actor,(await a.query('SELECT pg_backend_pid() pid')).rows[0].pid,(await b.query('SELECT pg_backend_pid() pid')).rows[0].pid);
  } finally {
    try {
      await a.query('ROLLBACK');await b.query('ROLLBACK');
      for (const o of scopes) {
        await a.query('DELETE FROM public.activities WHERE occasion=$1',[o]);
        await a.query('DELETE FROM public.activity_history WHERE occasion_id=$1',[o]);
        await a.query('DELETE FROM public.client_mutation_receipts WHERE occasion=$1',[o]);
        for (const t of ['client_commit_items','client_commit_components']) await a.query(`DELETE FROM public.${t} WHERE commit_id IN (SELECT commit_id FROM public.client_commits WHERE occasion=$1)`,[o]);
        await a.query('DELETE FROM public.client_commits WHERE occasion=$1',[o]);
        await a.query("DELETE FROM public.client_aggregate_versions WHERE scope_type='occasion' AND scope_id=$1",[o]);
        await a.query('DELETE FROM public.client_sync_private_scopes WHERE occasion=$1',[o]);
        await a.query('DELETE FROM public.occasion_users WHERE occasion=$1',[o]);
        await a.query('DELETE FROM public.occasions WHERE id=$1',[o]);
      }
    } finally {await a.end();await b.end();}
  }
}
const emptyHistory={schemaVersion:1,timeBasis:'UTC',activities:[],activity_assignments:[],assignmentPlaceLinks:[],assignmentEventLinks:[]};
async function publish(c,o,v,graph,parent=null) {
  const history=(await c.query('SELECT public.activity_graph_history_internal_v1(public.normalize_activity_graph_internal_v1($1,$2::jsonb,true)) history',[o,JSON.stringify(graph)])).rows[0].history;
  return c.query('SELECT public.publish_activities_client_sync_v1($1,$2,$3,$4::jsonb,$5::jsonb,$6) result',[o,randomUUID(),v,JSON.stringify(graph),JSON.stringify(history),parent]);
}
test('publish vs draft, same-base publish and consistent session snapshot use two connections',async()=>withActivityEditors(async(a,b,[o],actor,aPid,bPid)=>{
 await a.query('BEGIN');const winner=(await publish(a,o,0,[])).rows[0].result;
 const oldSession=(await b.query('SELECT public.get_activity_editor_session_v1($1) result',[o])).rows[0].result;
 assert.equal(oldSession.liveVersion,0);assert.equal(oldSession.latestPublishId,null);
 const pending=b.query('SELECT public.save_activity_draft_client_sync_v1($1,$2,0,$3::jsonb,NULL) result',[o,randomUUID(),JSON.stringify(emptyHistory)]);
 await blockedBy(a,bPid,aPid);await a.query('COMMIT');
 assert.equal((await pending).rows[0].result.status,'conflict');
 assert.equal((await publish(b,o,0,[])).rows[0].result.status,'conflict');
 const session=(await b.query('SELECT public.get_activity_editor_session_v1($1) result',[o])).rows[0].result;
 assert.equal(session.liveVersion,1);assert.equal(session.latestPublishId,winner.data.historyId);
 const oldDraft=(await a.query('SELECT public.save_activity_draft_client_sync_v1($1,$2,1,$3::jsonb,$4) result',[o,randomUUID(),JSON.stringify(emptyHistory),winner.data.historyId])).rows[0].result.data.draftId;
 const changed={...emptyHistory,activities:[{id:randomUUID(),title:'New draft',is_hidden:false,order:1,unit:null,data:null}]};
 await a.query('BEGIN');await a.query('SELECT public.save_activity_draft_client_sync_v1($1,$2,1,$3::jsonb,$4)',[o,randomUUID(),JSON.stringify(changed),winner.data.historyId]);
 const discard=b.query('SELECT public.discard_activity_draft_client_sync_v1($1,$2,$3) result',[o,randomUUID(),oldDraft]);
 await blockedBy(a,bPid,aPid);await a.query('COMMIT');assert.equal((await discard).rows[0].result.status,'conflict');
}));
for (const collision of ['activity','assignment']) test(`global ${collision} UUID collision across occasions cannot transfer ownership`,async()=>withActivityEditors(async(a,b,[o1,o2],actor,aPid,bPid)=>{
 const shared=randomUUID();const activityA=randomUUID(),activityB=collision==='activity'?activityA:randomUUID();
 const graph=id=>[{id,title:'Collision',is_hidden:false,order:1,assignments:[{id:shared,user:actor,start_time:'2026-10-07T10:00:00Z',end_time:'2026-10-07T11:00:00Z',linked_place_ids:[],linked_event_ids:[]}]}];
 // Prepare both DTOs before either transaction commits; B's prechecks see no UUID owner.
 const first=graph(activityA),second=graph(activityB);
 const h1=(await a.query('SELECT public.activity_graph_history_internal_v1(public.normalize_activity_graph_internal_v1($1,$2::jsonb,true)) h',[o1,JSON.stringify(first)])).rows[0].h;
 const h2=(await b.query('SELECT public.activity_graph_history_internal_v1(public.normalize_activity_graph_internal_v1($1,$2::jsonb,true)) h',[o2,JSON.stringify(second)])).rows[0].h;
 await a.query('BEGIN');await a.query('SELECT public.publish_activities_client_sync_v1($1,$2,0,$3::jsonb,$4::jsonb,NULL)',[o1,randomUUID(),JSON.stringify(first),JSON.stringify(h1)]);
 const waiting=b.query('SELECT public.publish_activities_client_sync_v1($1,$2,0,$3::jsonb,$4::jsonb,NULL)',[o2,randomUUID(),JSON.stringify(second),JSON.stringify(h2)]);
 // Register rejection immediately so Node does not classify it as unhandled.
 const checked=assert.rejects(waiting,e=>e.code==='22023');
 await blockedBy(a,bPid,aPid);await a.query('COMMIT');await checked;
 const owner=(await a.query('SELECT a.occasion FROM public.activities a JOIN public.activity_assignments aa ON aa.activity_id=a.id WHERE aa.id=$1',[shared])).rows[0].occasion;
 assert.equal(owner,o1);assert.equal((await a.query('SELECT count(*)::int n FROM public.activities WHERE occasion=$1',[o2])).rows[0].n,0);
}));

test('leader authorization is rechecked after waiting for a group edit',async()=>withActivityEditors(async(a,b,[o],actor,aPid,bPid)=>{
 const org=(await a.query('SELECT organization FROM public.occasions WHERE id=$1',[o])).rows[0].organization;
 const email=`leader-${randomUUID()}@test.local`;
 const leader=(await a.query("SELECT public.create_user_in_organization_with_data_pure($1,$2,$2,'test-only-password','{\"name\":\"Leader\",\"surname\":\"Test\",\"sex\":\"male\"}'::jsonb) id",[org,email])).rows[0].id;
 let group;
 try{
  await a.query('INSERT INTO public.occasion_users(occasion,"user",is_approved) VALUES($1,$2,true)',[o,leader]);
  const dto={title:'Leader race',participants:[{user_id:leader,is_admin:true}]};
  group=(await a.query('SELECT public.save_user_group_client_sync_v1($1,$2,NULL,$3::jsonb) result',[o,randomUUID(),JSON.stringify(dto)])).rows[0].result.data.group.id;
  await b.query("SELECT set_config('request.jwt.claim.sub',$1,false)",[leader]);
  await a.query('BEGIN');
  await a.query('SELECT public.save_user_group_client_sync_v1($1,$2,1,$3::jsonb)',[o,randomUUID(),JSON.stringify({...dto,id:group,participants:[{user_id:leader,is_admin:false}]})]);
  const command=randomUUID();
  const pending=b.query('SELECT public.save_user_group_client_sync_v1($1,$2,1,$3::jsonb)',[o,command,JSON.stringify({...dto,id:group,description:'Stale leader'})]);
  const rejection=assert.rejects(pending,error=>error.code==='42501');
  await blockedBy(a,bPid,aPid);
  await a.query('COMMIT');
  await rejection;
  assert.equal((await a.query('SELECT count(*)::int n FROM public.client_mutation_receipts WHERE command_id=$1',[command])).rows[0].n,0);
 }finally{
  await a.query('ROLLBACK');await b.query('ROLLBACK');
  if(group){await a.query('DELETE FROM public.user_groups WHERE "group"=$1',[group]);await a.query('DELETE FROM public.user_group_info WHERE id=$1',[group]);}
  await a.query('DELETE FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[o,leader]);
  await a.query('DELETE FROM public.user_info WHERE id=$1',[leader]);await a.query('DELETE FROM auth.users WHERE id=$1',[leader]);
 }
}));

test('order membership teardown serializes against stale group and activity editors',async()=>withActivityEditors(async(a,b,[o],actor,aPid,bPid)=>{
 const scope=(await a.query('SELECT organization,unit FROM public.occasions WHERE id=$1',[o])).rows[0];
 const prior=(await a.query('SELECT is_manager FROM public.unit_users WHERE unit=$1 AND "user"=$2',[scope.unit,actor])).rows;
 const email=`order-member-${randomUUID()}@test.local`;
 const member=(await a.query("SELECT public.create_user_in_organization_with_data_pure($1,$2,$2,'test-only-password','{\"name\":\"Ticket\",\"surname\":\"Member\",\"sex\":\"male\"}'::jsonb) id",[scope.organization,email])).rows[0].id;
 let group,order;
 try{
  if(prior.length)await a.query('UPDATE public.unit_users SET is_manager=true WHERE unit=$1 AND "user"=$2',[scope.unit,actor]);
  else await a.query('INSERT INTO public.unit_users(unit,"user",is_manager) VALUES($1,$2,true)',[scope.unit,actor]);
  await a.query('UPDATE public.occasion_users SET is_manager=true WHERE occasion=$1 AND "user"=$2',[o,actor]);
  order=(await a.query("INSERT INTO eshop.orders(order_sequence,order_symbol,occasion,state,data,price,currency_code) VALUES(public.next_order_sequence($1),public.generate_order_symbol(),$1,'ordered','{}',100,'CZK') RETURNING id",[o])).rows[0].id;
  const ticket=(await a.query("INSERT INTO eshop.tickets(occasion,state,ticket_symbol) VALUES($1,'ordered',$2) RETURNING id",[o,randomUUID()])).rows[0].id;
  await a.query('INSERT INTO eshop.order_product_ticket("order",ticket) VALUES($1,$2)',[order,ticket]);
  await a.query('INSERT INTO public.occasion_users(occasion,"user",ticket,is_approved) VALUES($1,$2,$3,true)',[o,member,ticket]);
  const dto={title:'Order member group',participants:[{user_id:member}]};
  group=(await a.query('SELECT public.save_user_group_client_sync_v1($1,$2,NULL,$3::jsonb) result',[o,randomUUID(),JSON.stringify(dto)])).rows[0].result.data.group.id;
  const activity=randomUUID();await a.query('INSERT INTO public.activities(id,occasion,title,is_hidden,"order") VALUES($1,$2,\'Order task\',false,0)',[activity,o]);
  await a.query('INSERT INTO public.activity_assignments(id,activity_id,"user",start_time,end_time) VALUES($1,$2,$3,now(),now()+interval \'1 hour\')',[randomUUID(),activity,member]);
  await a.query('BEGIN');await a.query('SELECT public.delete_order_client_sync_v1($1,$2)',[order,randomUUID()]);
  const stale=b.query('SELECT public.save_user_group_client_sync_v1($1,$2,1,$3::jsonb) result',[o,randomUUID(),JSON.stringify({...dto,id:group,participants:[],title:'Stale title'})]);
  await blockedBy(a,bPid,aPid);await a.query('COMMIT');
  assert.equal((await stale).rows[0].result.status,'conflict');
  assert.equal((await publish(b,o,0,[])).rows[0].result.status,'conflict');
  assert.equal((await a.query('SELECT count(*)::int n FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[o,member])).rows[0].n,0);
 }finally{
  await a.query('ROLLBACK');await b.query('ROLLBACK');
  if(group){await a.query('DELETE FROM public.user_groups WHERE "group"=$1',[group]);await a.query('DELETE FROM public.user_group_info WHERE id=$1',[group]);}
  await a.query('DELETE FROM public.occasion_users WHERE occasion=$1 AND "user"=$2',[o,member]);
  await a.query('DELETE FROM public.user_info WHERE id=$1',[member]);await a.query('DELETE FROM auth.users WHERE id=$1',[member]);
  if(prior.length)await a.query('UPDATE public.unit_users SET is_manager=$3 WHERE unit=$1 AND "user"=$2',[scope.unit,actor,prior[0].is_manager]);
  else await a.query('DELETE FROM public.unit_users WHERE unit=$1 AND "user"=$2',[scope.unit,actor]);
 }
}));
