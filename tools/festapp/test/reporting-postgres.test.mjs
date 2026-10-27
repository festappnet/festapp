import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup as programSetup} from './program-fixtures.mjs';
import {Operations} from '../src/operations/catalog.mjs';
import {reportingDescriptors,csvPage} from '../src/operations/reporting.mjs';
import {PreviewArtifacts} from '../src/operations/preview.mjs';
import {denied} from './form-fixtures.mjs';
import {invokeOrderOperation} from '../src/operations/orders.mjs';
async function setup(t){const s=await programSetup(t);await s.db.query('RESET ROLE');
 for(const name of ['synchronization/get_client_activity_v1.sql','eshop_orders/repair_order_email_client_sync_v1.sql','emails/email_reporting.sql'])await s.db.query(await readFile(new URL('../../../database/functions/'+name,import.meta.url),'utf8'));
 await s.db.query(await readFile(new URL('../../../supabase/migrations/20261027180000_reporting_exports.sql',import.meta.url),'utf8'));
 await s.db.query('SET LOCAL ROLE authenticated');
 const artifacts=new PreviewArtifacts();const owner={...s.owner,profile:{...s.owner.profile,binding:'report:'+s.f.actor},allowedOperations:reportingDescriptors.map(d=>d.id),delegatedUnitContext:async(_client,unit)=>{assert.equal(unit,s.f.unit);return{organizationId:s.f.org,unitId:unit};}};
 const ops=new Operations(owner,{artifacts});return{...s,ops,owner,artifacts,call:async(op,args={})=>{const result=await ops.invoke(op,{occasionId:s.f.occasion,...args});assert.equal(result.ok,true,JSON.stringify(result));return result.data;}};
}
function content(result){return Buffer.from(result.contents[0].blob,'base64').toString('utf8');}
test('canonical audit is narrowed before paging despite broader ordinary unit/tenant roles; ties do not omit entries',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');await s.db.query('insert into organization_users(organization,"user",is_admin) values($1,$2,true)',[s.f.org,s.f.actor]);
 const own=[randomUUID(),randomUUID()],unitId=randomUUID(),organizationId=randomUUID();const at='2030-01-01T00:00:00.123456Z';
 for(const [key,value,commit] of [['occasion',s.f.occasion,own[0]],['occasion',s.f.occasion,own[1]],['unit',s.f.unit,unitId],['organization',s.f.org,organizationId]])await s.db.query('insert into client_commits('+key+',commit_id,occurred_at,actor_id,actor_kind,source,change_class) values($1,$2,$3,$4,\'user\',\'test.audit\',\'configuration\')',[value,commit,at,s.f.actor]);
 await s.db.query('SET LOCAL ROLE authenticated');
 const first=await s.call('history.commits',{limit:1});const second=await s.call('history.commits',{limit:1,before:first.nextCursor});assert.notEqual(first.items[0].commitId,second.items[0].commitId);assert.deepEqual(new Set([first.items[0].commitId,second.items[0].commitId]),new Set(own));
 const all=await s.call('history.commits',{limit:100});assert(!all.items.some(x=>x.commitId===unitId||x.commitId===organizationId));
 const broadened=await s.call('history.commits',{includeUnit:true,unitId:s.f.unit,limit:100});assert(broadened.items.some(x=>x.commitId===unitId));assert(!broadened.items.some(x=>x.commitId===organizationId));
 const deniedDetail=await s.ops.invoke('history.commit',{occasionId:s.f.occasion,commitId:unitId});assert.equal(deniedDetail.ok,false);assert.equal(deniedDetail.error.code,'FORBIDDEN');
 const legacy=(await s.db.query('select get_client_commits_v1($1,null,null,100) value',[s.f.occasion])).rows[0].value;assert(legacy.data.some(x=>x.commitId===organizationId),'ordinary UI retains its original broader audit view');
});
test('CSV selects only requested columns, escapes hostile text, pages without repeats and reauthorizes the artifact',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');await s.db.query('update user_info set name=$1 where id=$2',['=HYPERLINK("untrusted")',s.f.actor]);
 for(let n=0;n<2;n++){const alias='export-'+randomUUID();await s.db.query('select create_user_for_test($1,$2)',[alias,alias+'@example.invalid']);await s.db.query('insert into occasion_users(occasion,"user",data) values($1,get_user_id($2),\'{"note":"must not be exported"}\')',[s.f.occasion,alias]);}
 await s.db.query('SET LOCAL ROLE authenticated');let cursor;const ids=new Set();let first;
 for(let n=0;n<4;n++){const page=await s.call('exports.people',{limit:1,columns:['userId','name'],...(cursor?{after:cursor}:{})});if(!first)first=page;const text=content(await s.ops.readArtifact(page.file.uri));assert(!text.includes('must not be exported'));if(page.rowCount){const match=text.match(/[0-9a-f]{8}-[0-9a-f-]{27}/);assert(match);assert(!ids.has(match[0]));ids.add(match[0]);}cursor=page.nextCursor;if(!cursor)break;}
 assert.equal(ids.size,3);
 const direct=csvPage(['note'],[{note:'=HYPERLINK("bad")'},{note:' \t=SUM(1,2)'},{note:'multi\nline, "quote"'}]);assert(direct.includes("'="));assert(direct.includes("' \t="));assert(direct.includes('""quote""'));
 await denied(s.db,'select get_authoring_export_page($1,$2,$3,$4,$5,null,10)',[s.f.occasion,s.f.org,s.f.unit,'people',JSON.stringify(['secret'])],'22023');
 const other=new Operations({...s.owner,profile:{...s.owner.profile,binding:'different-connection'}},{artifacts:s.artifacts});await assert.rejects(other.readArtifact(first.file.uri),e=>e.code==='FORBIDDEN');
 await s.db.query('RESET ROLE');await s.db.query('update occasion_users set is_manager=false where occasion=$1 and "user"=$2',[s.f.occasion,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');await assert.rejects(s.ops.readArtifact(first.file.uri),e=>e.code==='FORBIDDEN');
});
test('report export is the exact canonical SQL report; a fresh hosted-style Operations instance can read the shared artifact',async t=>{
 const s=await setup(t);const baseline=await invokeOrderOperation(s.owner,s.client,'orders.report',{occasionId:s.f.occasion});
 const exported=await s.call('reports.export');const next=new Operations(s.owner,{artifacts:s.artifacts});const raw=JSON.parse(content(await next.readArtifact(exported.file.uri)));
 // generated_at is an authoritative report timestamp, not a derived total.
 delete raw.report.generated_at;delete baseline.report.generated_at;assert.deepEqual(raw,baseline);
});
test('bounded order history withholds raw historical QR/secret snapshots and binds the stored order',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');const form=Number((await s.db.query("insert into forms(occasion,title) values($1,'History fixture') returning id",[s.f.occasion])).rows[0].id);
 const order=Number((await s.db.query("insert into eshop.orders(occasion,form,state,order_symbol,order_sequence,data) values($1,$2,'ordered',generate_order_symbol(),1,'{}') returning id",[s.f.occasion,form])).rows[0].id);
 for(let n=0;n<2;n++)await s.db.query('insert into eshop.orders_history("order",state,price,currency_code,data) values($1,\'ordered\',100,\'CZK\',\'{"secret":"private-qr-payload"}\')',[order]);await s.db.query('SET LOCAL ROLE authenticated');
 const page=await s.call('history.orders',{orderId:order,limit:1});assert.equal(page.items.length,1);assert.equal(page.items[0].price,'100.00');assert(!JSON.stringify(page).includes('private-qr-payload'));
 const rest=await s.call('history.orders',{orderId:order,limit:1,beforeId:page.nextCursor});assert.notEqual(rest.items[0].id,page.items[0].id);
 const foreign=await s.ops.invoke('history.orders',{occasionId:s.f.occasion,orderId:order+999999});assert.equal(foreign.error.code,'FORBIDDEN');
});
test('activity uses the existing 31-day report and feedback uses the exact current UI projection',async t=>{
 const s=await setup(t);const from='2026-10-01T00:00:00Z',to='2026-10-02T00:00:00Z';
 const expected=(await s.db.query('select get_client_activity_v1($1,$2,$3) value',[s.f.occasion,from,to])).rows[0].value;
 assert.deepEqual((await s.call('history.activity',{from,to})).days,expected.data);
 await s.db.query('RESET ROLE');await s.db.query("update occasions set features=features||'[{\"code\":\"event_feedback\",\"is_enabled\":true}]' where id=$1",[s.f.occasion]);
 const event=Number((await s.db.query("insert into events(occasion,title,start_time,end_time) values($1,'Feedback',now(),now()+interval '1 hour') returning id",[s.f.occasion])).rows[0].id);
 await s.db.query('insert into event_feedback(occasion,event,"user",rating,note) values($1,$2,$3,\'happy\',\'Good\')',[s.f.occasion,event,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 const ordinary=(await s.db.query('select get_event_feedback_export_for_edit($1) value',[s.f.occasion])).rows[0].value;
 const page=await s.call('feedback.list',{limit:10});assert.deepEqual(page.items,ordinary.data);assert(!JSON.stringify(page).includes('client_id'));
});

test('an oversized audit entry is rejected before an unbounded detail payload crosses RPC',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');const id=randomUUID();
 await s.db.query("insert into client_commits(occasion,commit_id,actor_id,actor_kind,source,change_class) values($1,$2,$3,'user','test.large-audit','configuration')",[s.f.occasion,id,s.f.actor]);
 await s.db.query("insert into client_commit_items(commit_id,item_index,entity_type,entity_id,operation,safe_label,changed_fields) select $1,n,'test',n::text,'update','Safe item',ARRAY['title'] from generate_series(0,500) n",[id]);await s.db.query('SET LOCAL ROLE authenticated');
 const result=await s.ops.invoke('history.commit',{occasionId:s.f.occasion,commitId:id});assert.equal(result.ok,false);assert.equal(result.error.code,'HISTORY_ENTRY_OR_RANGE_REJECTED');
});
