import test from 'node:test';
import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {setup} from './finance-fixtures.mjs';
import {denied} from './form-fixtures.mjs';
const agenda=(s,action,payload={},id=null)=>s.db.query('select manage_unit_agenda($1,$2,$3,$4,$5) value',[s.f.unit,s.f.org,action,payload,id]).then(r=>r.rows[0].value);
test('quotes use the existing information version, conflict and receipt owner',async t=>{
 const s=await setup(t);const quote={title:'Quote',description:'Text',type:'quote',isHidden:false,order:0,data:{date:'2026-10-27T00:00:00Z'}};
 const first=await agenda(s,'quotes.save',{expectedVersion:null,quote},randomUUID());assert.equal(first.code,200);const row=first.data.information;const stored=(await agenda(s,'quotes.list')).items.find(x=>x.id===row.id);assert.equal(stored.description,'Text');
 const id=randomUUID(),payload={expectedVersion:first.data.version,quote:{...quote,id:row.id,description:'Edited'}};const saved=await agenda(s,'quotes.save',payload,id);assert.deepEqual(await agenda(s,'quotes.save',payload,id),saved);
 assert.equal((await agenda(s,'quotes.save',payload,randomUUID())).code,409);
 const del=randomUUID(),target={quoteId:row.id,expectedVersion:saved.data.version};assert.equal((await agenda(s,'quotes.delete',target,del)).code,200);assert.equal((await agenda(s,'quotes.delete',target,del)).code,200);
});
test('legal identity saves/submit share receipts with UI and never expose tenant reviewer notes',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');await s.db.query("update organizations set data=data||'{\"DEFAULT_URL\":\"https://fixture.invalid\"}' where id=$1",[s.f.org]);await s.db.query('SET LOCAL ROLE authenticated');
 const profile={legalName:'Organizer',countryCode:'CZ',registrationNumber:'06455361',vatId:'',address:{street:'Street 1',city:'Praha',postalCode:'11000'},contactEmail:'organizer@example.invalid',phone:'',website:''};
 const id=randomUUID();const payload={expectedRevision:0,profile};const saved=await agenda(s,'legal.save',payload,id);assert.equal(saved.code,200,JSON.stringify(saved));assert.deepEqual(await agenda(s,'legal.save',payload,id),saved);
 const submitted=await agenda(s,'legal.submit',{expectedRevision:saved.data.profile.revision},randomUUID());assert.equal(submitted.code,200,JSON.stringify(submitted));assert.equal(submitted.data.profile.status,'pending');
 const read=await agenda(s,'legal.inspect');assert(!JSON.stringify(read).includes('reviewNote'));assert(!JSON.stringify(read).includes('reviewSource'));
});
test('unit deletion retains original guards and actor-owned tombstone recovery',async t=>{
 const s=await setup(t);await denied(s.db,'select delete_unit_client_sync_v1($1,$2,$3)',[s.f.unit,randomUUID(),s.f.org],'P0001');
 await s.db.query('RESET ROLE');const unit=Number((await s.db.query("insert into units(title,organization) values('Disposable organizer',$1) returning id",[s.f.org])).rows[0].id);await s.db.query('insert into unit_users(unit,"user",is_manager) values($1,$2,true)',[unit,s.f.actor]);await s.db.query('SET LOCAL ROLE authenticated');
 const id=randomUUID();const first=(await s.db.query('select delete_unit_client_sync_v1($1,$2,$3) value',[unit,id,s.f.org])).rows[0].value;assert.equal(first.code,200);assert.deepEqual((await s.db.query('select delete_unit_client_sync_v1($1,$2,$3) value',[unit,id,s.f.org])).rows[0].value,first);
 await denied(s.db,'select delete_unit_client_sync_v1($1,$2,$3)',[unit,id,s.f.org+99999]);
});

test('physical order deletion and persisted history deletion share canonical owners and exact scoped tombstones',async t=>{
 const s=await setup(t);await s.db.query('RESET ROLE');const form=Number((await s.db.query("insert into forms(occasion,title) values($1,'Delete fixture') returning id",[s.f.occasion])).rows[0].id);
 const order=Number((await s.db.query("insert into eshop.orders(occasion,form,state,order_symbol,order_sequence,data) values($1,$2,'ordered',generate_order_symbol(),1,'{}') returning id",[s.f.occasion,form])).rows[0].id);
 const history=Number((await s.db.query("insert into eshop.orders_history(\"order\",state,data) values($1,'ordered','{}') returning id",[order])).rows[0].id);await s.db.query('SET LOCAL ROLE authenticated');
 const hid=randomUUID(),base=[history,hid,s.f.occasion,s.f.org,s.f.unit,order];const first=(await s.db.query('select delete_order_history_client_sync_v1($1,$2,$3,$4,$5,$6) value',base)).rows[0].value;assert.equal(first.code,200);assert.deepEqual((await s.db.query('select delete_order_history_client_sync_v1($1,$2,$3,$4,$5,$6) value',base)).rows[0].value,first);
 const context=(await s.db.query('select get_delegated_order_deletion_context($1,$2,$3,$4) value',[s.f.occasion,s.f.org,s.f.unit,order])).rows[0].value;const id=randomUUID();
 await denied(s.db,'select delete_delegated_order_client_sync_v1($1,$2,$3,$4,$5,$6)',[s.f.occasion,s.f.org,s.f.unit,order,id,'a'.repeat(64)],'40001');
 const args=[s.f.occasion,s.f.org,s.f.unit,order,id,context.revision];const deleted=(await s.db.query('select delete_delegated_order_client_sync_v1($1,$2,$3,$4,$5,$6) value',args)).rows[0].value;assert.equal(deleted.code,200);assert.deepEqual((await s.db.query('select delete_delegated_order_client_sync_v1($1,$2,$3,$4,$5,$6) value',args)).rows[0].value,deleted);
 await denied(s.db,'select delete_delegated_order_client_sync_v1($1,$2,$3,$4,$5,$6)',[s.f.occasion,s.f.org+99999,s.f.unit,order,id,context.revision]);
});
