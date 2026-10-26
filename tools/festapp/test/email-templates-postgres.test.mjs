import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {fixture} from '../../../automation/authorization/benchmark.mjs';
import {openDisposableDatabase} from './postgres.mjs';
import {Operations} from '../src/operations/catalog.mjs';
const connection=process.env.FESTAPP_MCP_TEST_DATABASE_URL;
// New evidence must never silently skip the actual database contract.
const options={skip:!connection};
const code='TICKET_ORDER_CONFIRMATION';
async function install(db){await db.query(await readFile(new URL('../../../supabase/migrations/20261026170000_email_template_commands.sql',import.meta.url),'utf8'));}
async function setup(t){const db=await openDisposableDatabase(connection);await db.query('BEGIN');t.after(async()=>{await db.query('ROLLBACK');await db.end();});await install(db);const f=await fixture(db,2);
 await db.query("insert into email_templates(code,subject,html,title,organization) values($1,'Org subject','<p>Org body {{name}}</p>','Org template',$2)",[code,f.org]);
 return {db,f};}
async function read(db,f,type='occasion',entity=f.occasion,selected=code){return (await db.query('select get_email_template_catalog($1,$2,$3,$4,$5) value',[type,entity,f.org,f.unit,selected])).rows[0].value;}
async function change(db,f,revision,{type='occasion',entity=f.occasion,action='save',payload={title:'Custom',subject:'Own subject',html:'<p>Own body</p>'},commandId=randomUUID()}={}){return (await db.query('select manage_email_template($1,$2,$3,$4,$5,$6,$7,$8,$9) value',[type,entity,f.org,f.unit,action,code,revision,payload,commandId])).rows[0].value;}
async function denied(db,sql,args,expected='42501'){await db.query('SAVEPOINT denied');await assert.rejects(db.query(sql,args),e=>e.code===expected);await db.query('ROLLBACK TO SAVEPOINT denied');await db.query('RELEASE SAVEPOINT denied');}
function executor(db,f){const calls=[];const scope=async()=>({organizationId:f.org,unitId:f.unit});const owner={root:'/tmp/festapp-email-template-tests',profile:{name:'fixture',organizationId:f.org,tenantId:'fixture'},allowedOperations:['email_templates.list','email_templates.inspect','email_templates.change','email_templates.banner.inspect','email_templates.banner.change'],delegatedContext:scope,delegatedUnitContext:scope,authorized:action=>action({rpc:async(name,args)=>{
 const params=Object.values(args);let data;
 // Preserve named argument identity, as PostgREST does.
 const names=Object.keys(args);const sql='select '+name+'('+names.map((n,i)=>n+'=> $'+(i+1)).join(',')+') value';
 try{data=(await db.query(sql,params)).rows[0].value;}catch(error){return{data:null,error};}
 calls.push({name,bytes:Buffer.byteLength(JSON.stringify(data)),entities:data.templates?.length??1});return{data,error:null};
 }},{userId:f.actor})};return{ops:new Operations(owner),calls};}

test('email effective source and bounded executor list reuse the administration resolver without HTML or unrelated entity data',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);
 const result=await ex.ops.invoke('email_templates.list',{entityType:'occasion',entityId:f.occasion});assert.equal(result.ok,true,JSON.stringify(result));assert(result.data.templates.length<=12);assert(result.data.templates.every(t=>!Object.hasOwn(t,'html')));
 const detail=await ex.ops.invoke('email_templates.inspect',{entityType:'occasion',entityId:f.occasion,code});assert.equal(detail.ok,true,JSON.stringify(detail));const row=detail.data.templates[0];assert.deepEqual(row.source,{type:'organization',id:f.org});
 const ui=(await db.query("select get_entity_email_templates('occasion',$1) value",[f.occasion])).rows[0].value;assert.equal(row.revision,ui.templates.find(t=>t.code===code).revision);assert.equal(row.html,'<p>Org body {{name}}</p>');
 assert.equal(ex.calls.length,2);t.diagnostic('email-data-network '+JSON.stringify(ex.calls));
});

test('UI/MCP saves and reset share one receipt and authoritative inheritance; no queue intent is created',options,async t=>{
 const{db,f}=await setup(t);const before=(await db.query('select count(*) n from email_messages')).rows[0].n;await db.query('SET LOCAL ROLE authenticated');let row=(await read(db,f)).templates[0];
 const ex=executor(db,f);const args={entityType:'occasion',entityId:f.occasion,code,expectedRevision:row.revision,commandId:randomUUID(),command:{action:'save',title:'Saved',subject:'MCP subject',html:'<p>Safe</p>'}};
 const saved=await ex.ops.invoke('email_templates.change',args);assert.equal(saved.ok,true,JSON.stringify(saved));assert.equal(saved.data.templates[0].source.type,'occasion');assert.equal(saved.data.templates[0].source.id,f.occasion);
 assert.equal((await ex.ops.invoke('email_templates.change',args)).ok,true);
 row=(await read(db,f)).templates[0];assert.equal(row.subject,'MCP subject');
 const reset=await change(db,f,row.revision,{action:'reset',payload:{}});assert.equal(reset.code,200);assert.equal(reset.data.templates[0].source.type,'organization');assert.equal(reset.data.templates[0].subject,'Org subject');
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*) n from client_mutation_receipts where command_id=$1',[args.commandId])).rows[0].n,'1');assert.equal((await db.query('select count(*) n from email_messages')).rows[0].n,before);
});

test('new override precondition catches concurrent creation and legacy edits; command UUID binds exact payload',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const original=(await read(db,f)).templates[0].revision;const id=randomUUID();assert.equal((await change(db,f,original,{commandId:id})).code,200);
 assert.equal((await change(db,f,original)).code,409);
 await denied(db,'select manage_email_template($1,$2,$3,$4,$5,$6,$7,$8,$9)',['occasion',f.occasion,f.org,f.unit,'save',code,original,{title:'Changed',subject:'Different',html:'x'},id],'22023');
 const current=(await read(db,f)).templates[0];await db.query('select update_email_template($1)',[{occasion:f.occasion,code,title:'Legacy',subject:'Legacy',html:'Legacy'}]);assert.equal((await change(db,f,current.revision)).code,409);
});

test('unit override is independent of occasion override; revoked roles, mixed hierarchy and private RPC grants fail closed',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const unitRow=(await read(db,f,'unit',f.unit)).templates[0];const unitSaved=await change(db,f,unitRow.revision,{type:'unit',entity:f.unit});assert.equal(unitSaved.code,200);assert.equal((await read(db,f)).templates[0].source.type,'unit');
 const occ=await change(db,f,(await read(db,f)).templates[0].revision);assert.equal(occ.code,200);assert.equal((await read(db,f,'unit',f.unit)).templates[0].source.type,'unit');
 await denied(db,'select get_email_template_catalog($1,$2,$3,$4,$5)',['occasion',f.occasion,f.org+999,f.unit,code]);await denied(db,'select get_email_template_catalog($1,$2,$3,$4,$5)',['occasion',f.occasion,f.org,f.unit+999,code]);
 await denied(db,'select get_email_template_catalog($1,$2,$3,$4,$5)',['occasion',f.occasion,f.org,f.unit,'INTERNAL_PRIVATE_CODE'],'22023');
 const revision=(await read(db,f)).templates[0].revision;const commandId=randomUUID();assert.equal((await change(db,f,revision,{commandId})).code,200);
 await db.query('RESET ROLE');await db.query('update occasion_users set is_editor=false,is_editor_view=false,is_editor_order=false,is_editor_order_view=false,is_manager=false where occasion=$1',[f.occasion]);await db.query('SET LOCAL ROLE authenticated');
 await denied(db,'select manage_email_template($1,$2,$3,$4,$5,$6,$7,$8,$9)',['occasion',f.occasion,f.org,f.unit,'save',code,revision,{title:'Custom',subject:'Own subject',html:'<p>Own body</p>'},commandId]);
 await db.query('RESET ROLE');for(const role of ['anon','service_role'])assert.equal((await db.query("select has_function_privilege($1,'get_email_template_catalog(text,bigint,bigint,bigint,text)','execute') allowed",[role])).rows[0].allowed,false);
 assert.equal((await db.query("select has_function_privilege('authenticated','get_email_template_state_internal(jsonb,text)','execute') allowed")).rows[0].allowed,false);
});

test('banner saves and resets return the sending wrapper and reject stale revisions and unsafe URLs',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const ex=executor(db,f);const scope={entityType:'occasion',entityId:f.occasion};let banner=(await ex.ops.invoke('email_templates.banner.inspect',scope)).data;
 const args={...scope,expectedRevision:banner.revision,commandId:randomUUID(),bannerUrl:'https://img.festapp.net/images/test-banner.png'};
 const saved=await ex.ops.invoke('email_templates.banner.change',args);assert.equal(saved.ok,true,JSON.stringify(saved));assert(saved.data.wrapperHtml.includes(args.bannerUrl));assert.equal((await ex.ops.invoke('email_templates.banner.change',args)).ok,true);
 assert.equal((await ex.ops.invoke('email_templates.banner.change',{...args,commandId:randomUUID()})).error.code,'EMAIL_TEMPLATE_CHANGED_RELOAD_REQUIRED');
 banner=saved.data;await denied(db,'select manage_email_banner($1,$2,$3,$4,$5,$6,$7)',['occasion',f.occasion,f.org,f.unit,banner.revision,'https://evil.invalid/banner" onerror="bad',randomUUID()],'22023');
 const reset=await ex.ops.invoke('email_templates.banner.change',{...scope,expectedRevision:banner.revision,commandId:randomUUID(),bannerUrl:null});assert.equal(reset.ok,true,JSON.stringify(reset));assert.equal(reset.data.overrideUrl,null);
 const preview=(await db.query("select get_email_template_preview_context('occasion',$1,$2,$3,$4) value",[f.occasion,f.org,f.unit,code])).rows[0].value;assert.equal(preview.template.code,code);assert.equal(preview.context.occasion,f.occasion);
});

test('two connections serialize competing override creation and lost-response replay without duplicate writes',options,async t=>{
 const admin=await openDisposableDatabase(connection),other=await openDisposableDatabase(connection);let f;
 t.after(async()=>{
  await other.query('ROLLBACK');await other.end();await admin.query('ROLLBACK');
  if(f){await admin.query('BEGIN');
   await admin.query('delete from client_mutation_receipts where occasion=$1 or unit=$2',[f.occasion,f.unit]);
   for(const table of ['client_commit_items','client_commit_components'])await admin.query(`delete from ${table} where commit_id in(select commit_id from client_commits where occasion=$1 or unit=$2)`,[f.occasion,f.unit]);
   await admin.query('delete from client_commits where occasion=$1 or unit=$2',[f.occasion,f.unit]);
   await admin.query("delete from client_aggregate_versions where (scope_type='occasion' and scope_id=$1) or (scope_type='unit' and scope_id=$2)",[f.occasion,f.unit]);
   await admin.query('delete from email_templates where organization=$1',[f.org]);await admin.query('delete from email_wrappers where organization=$1',[f.org]);
   for(const sql of ['delete from places where occasion=$1','delete from occasion_users where occasion=$1','delete from occasion_link_reservations where occasion=$1','delete from occasions where id=$1'])await admin.query(sql,[f.occasion]);
   await admin.query("delete from abuse_policy_overrides where (target_kind='unit' and target_id=$1) or (target_kind='organization' and target_id=$2)",[f.unit,f.org]);
   await admin.query('delete from unit_users where unit=$1',[f.unit]);await admin.query('delete from units where id=$1',[f.unit]);await admin.query('delete from user_info where id=$1',[f.actor]);await admin.query('delete from auth.users where id=$1',[f.actor]);await admin.query('delete from organizations where id=$1',[f.org]);await admin.query('COMMIT');
  }await admin.end();
 });
 await admin.query('BEGIN');await install(admin);f=await fixture(admin,1);await admin.query("insert into email_templates(code,subject,html,organization) values($1,'Ancestor','Ancestor',$2)",[code,f.org]);await admin.query('COMMIT');
 async function begin(db){await db.query('BEGIN');await db.query("set local statement_timeout='5s'");await db.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[f.actor]);await db.query('SET LOCAL ROLE authenticated');}
 await begin(admin);const revision=(await read(admin,f)).templates[0].revision;const commandId=randomUUID();const first=await change(admin,f,revision,{commandId});assert.equal(first.code,200);
 await begin(other);const competing=change(other,f,revision);await admin.query('COMMIT');assert.equal((await competing).code,409);await other.query('COMMIT');
 await begin(admin);await begin(other);const same=await change(admin,f,revision,{commandId});const replay=change(other,f,revision,{commandId});await admin.query('COMMIT');assert.equal((await replay).data.templates[0].id,same.data.templates[0].id);await other.query('COMMIT');
 assert.equal((await admin.query('select count(*) n from email_templates where occasion=$1 and code=$2',[f.occasion,code])).rows[0].n,'1');
});

test('failed completion rolls back the template and receipt; setup and editor share the ticket-block invariant',options,async t=>{
 const{db,f}=await setup(t);await db.query('SET LOCAL ROLE authenticated');const revision=(await read(db,f,'unit',f.unit)).templates[0].revision;
 await db.query('RESET ROLE');await db.query("create or replace function public.complete_unit_mutation_internal_v1(p_command_id uuid,p_unit bigint,p_source text,p_entity_type text,p_entity_id bigint,p_operation text,p_data jsonb) returns jsonb language plpgsql as $$ begin raise exception 'injected completion failure'; end $$");
 await db.query('SET LOCAL ROLE authenticated');const commandId=randomUUID();await denied(db,'select manage_email_template($1,$2,$3,$4,$5,$6,$7,$8,$9)',['unit',f.unit,f.org,f.unit,'save',code,revision,{title:'Custom',subject:'Own subject',html:'<p>Own body</p>'},commandId],'P0001');
 await db.query('RESET ROLE');assert.equal((await db.query('select count(*) n from email_templates where unit=$1 and occasion is null',[f.unit])).rows[0].n,'0');assert.equal((await db.query('select count(*) n from client_mutation_receipts where command_id=$1',[commandId])).rows[0].n,'0');
 await denied(db,'select validate_setup_email_templates_internal($1)',[{TICKET_ORDER_PAYMENT_DONE:{subject:'Subject',html:'{{tickets}}{{tickets}}'}}],'22023');
 await denied(db,'select update_email_template($1)',[{occasion:f.occasion,code:'TICKET_ORDER_PAYMENT_DONE',title:'Tickets',subject:'Subject',html:'{{tickets}}{{tickets}}'}],'22023');
});

test('every new/changed SQL owner matches the forward source contract and private helpers are inaccessible',options,async t=>{
 const{db}=await setup(t);const source=await readFile(new URL('../../../supabase/migrations/20261026170000_email_template_commands.sql',import.meta.url),'utf8');
 const names=new Set([...source.matchAll(/CREATE OR REPLACE FUNCTION public\.(\w+)/gi)].map(m=>m[1]));
 await db.query(await readFile(new URL('../../../database/tests/helpers/assertions.sql',import.meta.url),'utf8'));
 const contract=await readFile(new URL('../../../database/tests/canonical_mutation_source_parity_test.sql',import.meta.url),'utf8');
 const checks=contract.split('\n').filter(l=>[...names].some(n=>l.includes("to_regprocedure('public."+n+'(')));assert.equal(checks.length,names.size);await db.query('DO $$ BEGIN\n'+checks.join('\n')+'\nEND $$;');
 for(const name of ['get_email_banner_state_internal(jsonb)','lock_email_template_hierarchy_internal(jsonb)','validate_email_template_content_internal(text,text)'])assert.equal((await db.query("select has_function_privilege('authenticated',$1,'execute') allowed",[name])).rows[0].allowed,false);
 t.diagnostic('email SQL source owners '+names.size);
});
