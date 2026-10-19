// Actual nonpersonal source geometry replay with synthetic local owners/IDs.
// Full-corpus proof always rolls back. Explicit --retain-native-review-fixture=27
// retains only that synthetic local UI fixture; remote databases are forbidden.
import pg from 'pg';
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync,chmodSync,mkdirSync} from 'node:fs';
import {createHash,randomUUID} from 'node:crypto';
const root='/Users/miakh/source/festapp-blueprint-b-e2e-20261019/';
const source=JSON.parse(readFileSync(root+'private-existing-blueprints.json'));
const bundle=JSON.parse(readFileSync(root+'private-existing-blueprints-converted.json'));
const activity=JSON.parse(readFileSync(root+'private-existing-blueprints-activity.json'));
const url=new URL(process.env.BLUEPRINT_DATABASE_URL??'');
assert.equal(url.hostname,'127.0.0.1');assert.equal(url.port,'59522');
const c=new pg.Client({connectionString:url.href});
const hash=value=>createHash('sha256').update(value).digest('hex');
const namespace=Buffer.from('6ba7b8119dad11d180b400c04fd430c8','hex');
function v5(name){const b=createHash('sha1').update(namespace).update(name).digest().subarray(0,16);b[6]=(b[6]&15)|80;b[8]=(b[8]&63)|128;const s=b.toString('hex');return `${s.slice(0,8)}-${s.slice(8,12)}-${s.slice(12,16)}-${s.slice(16,20)}-${s.slice(20)}`;}
function sorted(value){return Array.isArray(value)?value.map(sorted):value&&typeof value==='object'?Object.fromEntries(Object.keys(value).sort().map(k=>[k,sorted(value[k])])):value;}
const rows=[];
const retainNativeFixture=process.argv.includes('--retain-native-review-fixture=27');
try{
 await c.connect();
 assert.equal((await c.query('select project from festapp_test_support.disposable_environment')).rows[0].project,'festapp-blueprint-b-e2e-20261019');
 await c.query('begin');
 const fixture=(await c.query('select o.organization,o.unit,o.occasion_hidden,ou."user" actor from public.occasions o join public.occasion_users ou on ou.occasion=o.id where o.id=1 and ou.is_editor order by ou."user" limit 1')).rows[0];assert(fixture);
 await c.query("select set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','authenticated',true)",[fixture.actor]);
 for(const original of source.blueprints.filter(b=>!retainNativeFixture||b.id===27)){
  const frozen=bundle.blueprints.find(b=>b.blueprintId===original.id);assert(frozen);assert.equal(hash(frozen.reviewedSourceText),original.conversionSourceSha256);
  const meta=original.occasionMeta;
  const occasion=(await c.query(`insert into public.occasions(title,organization,unit,link,start_time,end_time,is_hidden,is_open,occasion_hidden) values($1,$2,$3,$4,coalesce($5::timestamptz,now())-interval '1 day',$5,$6,$7,$8) returning id`,['Conversion replay '+original.id,fixture.organization,fixture.unit,'conversion-'+randomUUID(),meta.end_time,meta.is_hidden,meta.is_open,fixture.occasion_hidden])).rows[0].id;
  // Direct synthetic inserts must still register the canonical public link.
  // Creation mode avoids the existing-slug no-op intended for normal updates.
  await c.query("update public.occasions set link=public.reserve_public_link_internal('occasion',id,link,true) where id=$1",[occasion]);
  await c.query('insert into public.occasion_users(occasion,"user",is_editor,is_editor_order,is_editor_order_view) values($1,$2,true,true,true)',[occasion,fixture.actor]);
  const type=(await c.query("insert into eshop.product_types(occasion,title,type) values($1,'Reviewed seats','spot') returning id",[occasion])).rows[0].id;
  const products=new Map();
  for(const p of original.products){const made=(await c.query('insert into eshop.products(occasion,product_type,title,price,currency_code,is_hidden) values($1,$2,$3,$4,$5,false) returning id',[occasion,type,p.title,p.price,p.currency_code])).rows[0].id;products.set(p.id,made);}
  const blueprint=(await c.query('insert into eshop.blueprints(occasion,organization,title,configuration,objects,groups,background_svg) values($1,$2,$3,$4,$5,$6,$7) returning id',[occasion,fixture.organization,original.title,original.configuration,original.objects==null?null:JSON.stringify(original.objects),original.groups==null?null:JSON.stringify(original.groups),original.background_svg])).rows[0].id;
  const physical=original.spots.map(s=>({old_id:s.id,title:s.title,product:s.product==null?null:products.get(s.product),state:s.state}));
  const allocated=await c.query(`with input as(select * from jsonb_to_recordset($1::jsonb) as x(old_id bigint,title text,product bigint,state text)),
    allocated as materialized(select nextval(pg_get_serial_sequence('eshop.spots','id')) id,input.* from input),
    inserted as(insert into eshop.spots(id,occasion,blueprint,title,product,state) select id,$2,$3,title,product,state from allocated returning id)
    select allocated.old_id,allocated.id from allocated join inserted using(id)`,[JSON.stringify(physical),occasion,blueprint]);
  const spots=new Map(allocated.rows.map(s=>[Number(s.old_id),s.id]));assert.equal(spots.size,original.spots.length);
  const objects=original.objects==null?null:original.objects.map(o=>({...o,id:spots.get(o.id)}));
  await c.query('update eshop.blueprints set objects=$2 where id=$1',[blueprint,objects==null?null:JSON.stringify(objects)]);
  for(const f of original.forms)await c.query('insert into public.forms(occasion,blueprint,title,link,type,is_open) values($1,$2,$3,$4,$5,$6)',[occasion,blueprint,'Reviewed form','conversion-form-'+randomUUID(),f.type,f.is_open]);
  const prefix=`festapp:occasion:${occasion}:blueprint:${blueprint}:`,oldPrefix=`festapp:occasion:${original.occasion}:blueprint:${original.id}:`;
  const ids=new Map();for(const g of original.groups??[])ids.set(v5(oldPrefix+'group:'+g.id),v5(prefix+'group:'+g.id));
  for(const binding of frozen.request.seatChanges)ids.set(binding.nodeId,v5(prefix+'spot:'+spots.get(binding.spotId)));
  for(const node of frozen.reviewedNativePlan?.nodes??[])ids.set(v5(oldPrefix+'native:'+node.id),v5(prefix+'native:'+node.id));
  for(const binding of frozen.request.seatChanges)ids.set(v5(oldPrefix+'attachment:'+binding.nodeId),v5(prefix+'attachment:'+ids.get(binding.nodeId)));
  const remap=v=>typeof v==='string'&&ids.has(v)?ids.get(v):Array.isArray(v)?v.map(remap):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).map(([k,val])=>[k,remap(val)])):v;
  const request=remap(structuredClone(frozen.request));request.id=Number(blueprint);request.occasion=Number(occasion);request.organization=Number(fixture.organization);
  for(const binding of request.seatChanges){binding.spotId=Number(spots.get(binding.spotId));if(binding.productId!=null)binding.productId=Number(products.get(binding.productId));}
  for(const group of request.groupProductChanges)if(group.productId!=null)group.productId=Number(products.get(group.productId));
  if(request.layout.background)await c.query('select public.copy_blueprint_image_resources_internal(1,$1,$2)',[occasion,request.layout]);
  const isDemo=activity.blueprints.find(b=>b.blueprintId===original.id)?.isDemo===true;
  if(isDemo){const bank=(await c.query("insert into eshop.bank_accounts(title,type,supported_currencies) values('Reviewed demo replay','FIO',array['CZK']) returning id")).rows[0].id;await c.query("insert into public.demo_occasions(occasion,organization,demo_key,fixture_version,bank_account,is_listed,sort_order,description,reference_at) values($1,$2,'ball',$3,$4,false,1,'Reviewed source geometry replay',now())",[occasion,fixture.organization,'conversion-'+randomUUID(),bank]);}
  const reviewed=(await c.query('select public.blueprint_legacy_migration_source_internal($1) source',[blueprint])).rows[0].source;
  const text=JSON.stringify(sorted(reviewed)),sha=hash(text),command=randomUUID();
  const result=(await c.query('select public.migrate_blueprint_layout_reviewed_internal($1,$2,$3,$4) result',[text,sha,request,command])).rows[0].result;
  assert.equal(result.status,'applied',JSON.stringify({source:original.id,result}));assert.equal(result.data.seatBindings.length,physical.length);
  const fresh=(await c.query('select layout,layout_revision from eshop.blueprints where id=$1',[blueprint])).rows[0];assert.equal(Number(fresh.layout_revision),1);assert.deepEqual(fresh.layout,JSON.parse(JSON.stringify(request.layout)));
  const replay=(await c.query('select public.migrate_blueprint_layout_reviewed_internal($1,$2,$3,$4) result',[text,sha,request,command])).rows[0].result;assert.equal(replay.status,'applied');
  rows.push({localOccasionId:occasion,localBlueprintId:blueprint,occasionLink:(await c.query('select link from public.occasions where id=$1',[occasion])).rows[0].link,sourceBlueprintId:original.id,seats:physical.length,background:!!request.layout.background,isDemo,revision:1,replayed:true});
 }
 await c.query(retainNativeFixture?'commit':'rollback');
 const proof={passed:true,productionApplied:false,rolledBack:!retainNativeFixture,sourceBlueprintCount:source.blueprints.length,convertedCount:rows.length,stableSourceSpots:rows.reduce((n,r)=>n+r.seats,0),syntheticReferenceIds:true,rows};
 mkdirSync(root+'checks',{recursive:true,mode:0o700});const out=root+'checks/'+(retainNativeFixture?'native-editor-fixture.json':'all-existing-reviewed-conversion.json');writeFileSync(out,JSON.stringify(proof,null,2),{mode:0o600});chmodSync(out,0o600);
 console.log(`PASS ${rows.length}/${source.blueprints.length} actual-source layouts through reviewed SQL migration + replay; ${proof.stableSourceSpots} seats; ${retainNativeFixture?'synthetic local UI fixture retained':'full rollback'}`);
}finally{await c.query('rollback').catch(()=>{});await c.end();}
