import {setup} from './program-fixtures.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {setup as formSetup,denied} from './form-fixtures.mjs';
import {programDescriptors,invokeProgramOperation} from '../src/operations/program.mjs';
import {Operations} from '../src/operations/catalog.mjs';
import {createServer} from '../src/mcp/server.mjs';
import {Client,InMemoryTransport} from '@modelcontextprotocol/client';


function event(title='Program item') {return{title,startTime:new Date(Date.now()+3600000).toISOString(),endTime:new Date(Date.now()+7200000).toISOString(),maxParticipants:10,description:'Scoped program',placeId:null,splitForMenWomen:false,isGroupEvent:false,isHidden:false,type:null,data:{is_cancelled:false},order:0,parentEventIds:[],eventRoleIds:[]};}
const createEvent=s=>s.command('events.save',{expectedVersion:null,entity:event()});
const read=(s,domain,id)=>s.invoke(domain+'.inspect',{entityId:id});

test('schedule event and exclusive-group commands preserve full relationships, original version and frozen replay',async t=>{
 const s=await setup(t);const created=await createEvent(s);assert(created.entityId);
 const state=await read(s,'events',created.entityId);assert.equal(state.aggregateVersion,created.aggregateVersion);assert.equal(state.entity.title,'Program item');
 const request={entity:{...event('Confirmed edit'),id:created.entityId},expectedVersion:state.aggregateVersion,commandId:randomUUID()};const edited=await s.invoke('events.save',request);assert.deepEqual(await s.invoke('events.save',request),edited);
 await assert.rejects(s.command('events.save',{...request,commandId:randomUUID()}),e=>e.code==='PROGRAM_CHANGED_RELOAD_REQUIRED');
 const group=await s.command('exclusiveGroups.save',{expectedVersion:null,entity:{title:'Choose one',events:[created.entityId]}});assert(group.entityId);
 const g=await read(s,'exclusiveGroups',group.entityId);assert.equal(g.entity.exclusive_events[0].event,created.entityId);
 assert.equal((await s.command('exclusiveGroups.delete',{entityId:group.entityId,expectedVersion:g.aggregateVersion})).status,'applied');
 const current=await read(s,'events',created.entityId);assert.equal((await s.command('events.delete',{entityId:created.entityId,expectedVersion:current.aggregateVersion})).status,'applied');
});
test('map place/type/path and move delegate to their versioned owners without exposing an editor bundle',async t=>{
 const s=await setup(t);const place=await s.command('places.save',{expectedVersion:null,entity:{title:'Meeting point',description:'Here',type:null,coordinates:{latLng:{lat:50,lng:14}},isHidden:false,order:0,icon:null}});assert(place.entityId);
 const moved=await s.command('places.move',{entityId:place.entityId,expectedVersion:place.aggregateVersion,lat:51,lng:15});const p=await read(s,'places',place.entityId);assert.equal(p.aggregateVersion,moved.aggregateVersion);
 const type=await s.command('placeTypes.save',{expectedVersion:null,entity:{code:'rest',title:'Rest',icon:null,order:0,isHidden:false,isDefault:false}});assert(type.entityId);
 const path=await s.command('paths.save',{expectedVersion:null,entity:{title:'Walk',pathData:[[place.entityId,{lat:51.1,lng:15.1}]],data:{},icon:null,isHidden:false,order:0}});assert(path.entityId);
 const listed=await s.invoke('paths.list',{limit:1});assert.equal(listed.items.length,1);assert(!JSON.stringify(listed).includes('path_data'));
 for(const [domain,result] of [['paths',path],['placeTypes',type],['places',moved]])assert.equal((await s.command(domain+'.delete',{entityId:result.entityId,expectedVersion:result.aggregateVersion})).status,'applied');
});
test('speaker topics, event assignments and counseling slots reuse existing scoped commands',async t=>{
 const s=await setup(t);const e=await createEvent(s);
 const topic=await s.command('topics.save',{expectedVersion:null,entity:{title:'Topic',order:0,is_hidden:false}});assert(topic.entityId);
 const speaker=await s.command('speakers.save',{expectedVersion:null,entity:{title:'Speaker',subtitle:null,description:'Description',image:null,order:0,is_hidden:false,data:{},topics:[topic.entityId]}});assert(speaker.entityId);
 const inspected=await read(s,'speakers',speaker.entityId);assert.deepEqual(inspected.entity.topics,[topic.entityId]);
 const links=await s.invoke('eventSpeakers.inspect',{entityId:e.entityId});await s.command('eventSpeakers.save',{entityId:e.entityId,expectedVersion:links.aggregateVersion,speakerIds:[speaker.entityId]});assert.deepEqual((await s.invoke('eventSpeakers.inspect',{entityId:e.entityId})).speakerIds,[speaker.entityId]);
 const slots=await s.command('counseling.createSlots',{entityId:speaker.entityId,start:new Date(Date.now()+10800000).toISOString(),end:new Date(Date.now()+14400000).toISOString(),slotMinutes:30,placeId:null,capacity:1,title:'Counseling',breakMinutes:0});assert(slots.eventIds.length>0,JSON.stringify(slots));
 assert((await s.invoke('counseling.list',{entityId:speaker.entityId,limit:50})).items.length>=slots.eventIds.length);
 const first=await read(s,'events',slots.eventIds[0]);await s.command('counseling.deleteSlot',{entityId:speaker.entityId,eventId:slots.eventIds[0],expectedVersion:first.aggregateVersion});
 await s.command('counseling.deleteEmptySlots',{entityId:speaker.entityId,from:null});
});
test('activities draft, discard and publish share canonical UTC history and never expose unrelated contacts',async t=>{
 const s=await setup(t);const initial=await s.invoke('activities.inspect');assert.equal(initial.aggregateVersion,0);
 const graph=[{id:randomUUID(),title:'Help desk',description:null,type:null,unit:s.f.unit,is_hidden:false,order:0,data:{},assignments:[{id:randomUUID(),user:s.f.actor,start_time:new Date(Date.now()+10000).toISOString(),end_time:new Date(Date.now()+3600000).toISOString(),title:null,description:null,data:{},linked_place_ids:[],linked_event_ids:[]}]}];
 const saved=await s.command('activities.saveDraft',{expectedVersion:0,parentHistoryId:null,graph});assert(saved.draftId);
 const draft=await s.invoke('activities.inspect');assert.equal(draft.graph.length,0);assert.equal(draft.draftGraph.length,1);assert(!JSON.stringify(draft).includes('@example.invalid'));
 await s.command('activities.discardDraft',{expectedDraftId:saved.draftId});assert.equal((await s.invoke('activities.inspect')).draftId,null);
 const request={expectedVersion:0,parentHistoryId:null,graph,commandId:randomUUID()};const published=await s.invoke('activities.publish',request);assert.equal(published.aggregateVersion,1);assert.deepEqual(await s.invoke('activities.publish',request),published);assert.equal((await s.invoke('activities.inspect')).graph.length,1);
});
test('service definition edits are independent of participant assignments and exact replay survives later edits',async t=>{
 const s=await setup(t);const args={type:'food',code:'lunch',title:'Lunch',reference:null,commandId:randomUUID()};const created=await s.invoke('services.create',args);assert.equal(created.status,'applied');
 await s.command('services.update',{type:'food',code:'lunch',title:'Later lunch',reference:null});assert.deepEqual(await s.invoke('services.create',args),created);
 const list=await s.invoke('services.list',{type:'food',limit:50});assert.equal(list.items.find(x=>x.code==='lunch').title,'Later lunch');
 await s.command('services.delete',{type:'food',code:'lunch',force:false});assert.equal((await s.invoke('services.list',{type:'food',limit:50})).items.length,0);
});
test('unsupported variant, disabled features, foreign IDs and live role loss fail before reading or replay',async t=>{
 const s=await setup(t);const request={expectedVersion:null,entity:event(),commandId:randomUUID()};const e=await s.invoke('events.save',request);
 await denied(s.db,'select manage_program_authoring($1,$2,$3,$4,$5,null)',[s.f.occasion,s.f.org+1,s.f.unit,'events.inspect',{entityId:e.entityId}]);
 await s.db.query('RESET ROLE');await s.db.query("update organizations set data=data||'{\"IS_APP_SUPPORTED\":false}' where id=$1",[s.f.org]);await s.db.query('SET LOCAL ROLE authenticated');await assert.rejects(s.invoke('events.list',{limit:50}),x=>x.code==='FORBIDDEN');
 await s.db.query('RESET ROLE');await s.db.query("update organizations set data=data||'{\"IS_APP_SUPPORTED\":true}' where id=$1",[s.f.org]);await s.db.query("update occasions set features='[]' where id=$1",[s.f.occasion]);await s.db.query('SET LOCAL ROLE authenticated');await assert.rejects(s.invoke('activities.inspect'),x=>x.code==='FORBIDDEN');
 await s.db.query('RESET ROLE');await s.db.query('update occasion_users set is_editor=false,is_editor_view=false where occasion=$1 and "user"=$2',[s.f.occasion,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');await assert.rejects(s.invoke('events.save',request),x=>x.code==='FORBIDDEN');
});
test('actual SDK executes the scoped schedule command and attendance uses its existing owner',async t=>{
 const s=await setup(t);const ops=new Operations(s.owner),server=createServer(ops),sdk=new Client({name:'program-fixture',version:'1'});const [a,b]=InMemoryTransport.createLinkedPair();await server.connect(a);await sdk.connect(b);t.after(async()=>{await sdk.close();await server.close();});
 const created=await sdk.callTool({name:'festapp_events_save',arguments:{occasionId:s.f.occasion,expectedVersion:null,commandId:randomUUID(),entity:event()}});assert.equal(created.structuredContent.ok,true,JSON.stringify(created));
 const e=created.structuredContent.data.entityId;const attendance=await s.command('attendance.set',{entityId:e,participantId:s.f.actor,action:'sign_in'});assert.equal(attendance.isSignedIn,true,JSON.stringify(attendance));
 const removed=await s.command('attendance.set',{entityId:e,participantId:s.f.actor,action:'sign_out'});assert.equal(removed.isSignedIn,false);
});
