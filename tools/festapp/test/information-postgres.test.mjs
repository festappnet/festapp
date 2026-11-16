import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {setup,options} from './form-fixtures.mjs';
import {invokeInformationOperation} from '../src/operations/information.mjs';
async function fixture(t){
 const{db,f}=await setup(t);
 const owner={delegatedContext:async()=>({organizationId:f.org,unitId:f.unit})};
 const client={rpc:async(name,args)=>{
  assert.equal(name,'manage_information_authoring');
  await db.query('savepoint information_rpc');
  try{const data=(await db.query('select manage_information_authoring($1,$2,$3,$4,$5,$6) value',[args.p_occasion,args.p_organization,args.p_unit,args.p_action,args.p_payload,args.p_command_id])).rows[0].value;await db.query('release savepoint information_rpc');return{data};}
  catch(error){await db.query('rollback to savepoint information_rpc');await db.query('release savepoint information_rpc');return{error};}
 }};
 await db.query('set local role authenticated');
 const invoke=(operation,args={})=>invokeInformationOperation(owner,client,'information.'+operation,{occasionId:f.occasion,...args});
 return{db,f,owner,invoke};
}
const page={title:'Fotogalerie z minulých let',description:'<p>2016-2024 galleries</p>',type:null,isHidden:false,order:4,data:{presentation:'expandable'}};
test('information adapter preserves complete editor content, native receipts, CAS and ordinary-only projections',options,async t=>{
 const s=await fixture(t),{db,f,invoke}=s;
 const created=await invoke('save',{commandId:randomUUID(),expectedVersion:null,information:page});assert.equal(created.aggregateVersion,1);
 const id=created.information.id;
 const original=await invoke('inspect',{informationId:id});assert.deepEqual(original.information,{id,...page});
 const commandId=randomUUID(),information={...original.information,description:'<p>2016-2025 galleries</p>'};
 const saved=await invoke('save',{commandId,expectedVersion:original.aggregateVersion,information});assert.equal(saved.aggregateVersion,2);assert.equal(saved.status,'applied');
 assert.deepEqual(await invoke('save',{commandId,expectedVersion:1,information}),saved);
 await assert.rejects(invoke('save',{commandId:randomUUID(),expectedVersion:1,information}),{code:'INFORMATION_CHANGED_RELOAD_REQUIRED'});
 const later={...information,description:'<p>A later approved edit</p>'};
 await invoke('save',{commandId:randomUUID(),expectedVersion:2,information:later});
 assert.deepEqual(await invoke('save',{commandId,expectedVersion:1,information}),saved,'receipt replay retains its original snapshot after a later edit');
 assert.deepEqual((await invoke('inspect',{informationId:id})).information,later);
 await db.query('reset role');
 assert.equal(Number((await db.query('select count(*) n from client_mutation_receipts where command_id=$1',[commandId])).rows[0].n),1);
 const hidden=Number((await db.query("insert into information_hidden(occasion,data) values($1,'{\"answer\":\"private-game-answer\"}') returning id",[f.occasion])).rows[0].id);
 const game=Number((await db.query("insert into information(occasion,title,type,description,information_hidden) values($1,'Game','game','Private game',$2) returning id",[f.occasion,hidden])).rows[0].id);
 await db.query('set local role authenticated');
 const listed=await invoke('list',{limit:100});assert.deepEqual(listed.items.map(x=>x.id),[id]);assert(!JSON.stringify(listed).includes('answer'));
 await assert.rejects(invoke('inspect',{informationId:game}),{code:'FORBIDDEN'});
 await assert.rejects(invoke('save',{commandId:randomUUID(),expectedVersion:0,information:{...page,id:game}}),{code:'FORBIDDEN'});
 await assert.rejects(invoke('save',{commandId:randomUUID(),expectedVersion:null,information:{...page,type:'game',hiddenData:{answer:'secret'}}}),{code:'INFORMATION_REJECTED'});
 await db.query('reset role');const acl=(await db.query("select has_function_privilege('anon','public.manage_information_authoring(bigint,bigint,bigint,text,jsonb,uuid)','execute') anonymous,has_function_privilege('authenticated','public.manage_information_authoring(bigint,bigint,bigint,text,jsonb,uuid)','execute') ordinary")).rows[0];assert.deepEqual(acl,{anonymous:false,ordinary:true});
});
test('information tenant/unit binding, moved occasions and current role revocation guard reads, writes and replay',options,async t=>{
 const s=await fixture(t),{db,f,owner,invoke}=s;
 const commandId=randomUUID(),args={commandId,expectedVersion:null,information:page};
 const created=await invoke('save',args);
 owner.delegatedContext=async()=>({organizationId:f.org+1000000,unitId:f.unit});await assert.rejects(invoke('list'),{code:'FORBIDDEN'});
 owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit+1000000});await assert.rejects(invoke('save',args),{code:'FORBIDDEN'});
 owner.delegatedContext=async()=>({organizationId:f.org,unitId:f.unit});
 await db.query('reset role');const other=Number((await db.query("insert into units(title,organization) values('Another organizer',$1) returning id",[f.org])).rows[0].id);
 await db.query('update occasions set unit=$1 where id=$2',[other,f.occasion]);await db.query('set local role authenticated');
 await assert.rejects(invoke('inspect',{informationId:created.information.id}),{code:'FORBIDDEN'});await assert.rejects(invoke('save',args),{code:'FORBIDDEN'});
 await db.query('reset role');await db.query('update occasions set unit=$1 where id=$2',[f.unit,f.occasion]);
 await db.query('update unit_users set is_manager=false,is_editor=false,is_editor_view=false where unit=$1 and "user"=$2',[f.unit,f.actor]);
 await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_manager=false where occasion=$1 and "user"=$2',[f.occasion,f.actor]);
 await db.query('set local role authenticated');
 await assert.rejects(invoke('inspect',{informationId:created.information.id}),{code:'FORBIDDEN'});
 await assert.rejects(invoke('save',args),{code:'FORBIDDEN'});
});
