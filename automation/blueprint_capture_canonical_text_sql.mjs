import pg from '../web_client/node_modules/pg/lib/index.js';
import {readFileSync,writeFileSync} from 'node:fs';
import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);
const fixture=JSON.parse(readFileSync(new URL('test/fixtures/blueprint/canonical-text-scene.json',root),'utf8'));
const vectorImport=JSON.parse(readFileSync(new URL('test/fixtures/blueprint/canonical-vector-import.json',root),'utf8'));
fixture.document.nodes.push(vectorImport.node);
const rowImport=JSON.parse(readFileSync(new URL('test/fixtures/blueprint/canonical-row-import.json',root),'utf8'));
const couch=JSON.parse(readFileSync(new URL('test/fixtures/blueprint/canonical-couch-authoring.json',root),'utf8'));
rowImport.document.nodes.push(...couch.document.nodes);
rowImport.document.attachments.push(...couch.document.attachments);
fixture.document.selectionUnits=[...fixture.document.selectionUnits??[],...couch.document.selectionUnits];
fixture.document.nodes.push(...rowImport.document.nodes);
fixture.document.attachments.push(...rowImport.document.attachments);
const client=new pg.Client({connectionString:'postgresql://supabase_admin:postgres@127.0.0.1:59522/postgres'});
await client.connect();
try{
 const marker=await client.query('SELECT project FROM festapp_test_support.disposable_environment WHERE singleton');
 assert.equal(marker.rows[0]?.project,'festapp-blueprint-b-e2e-20261019');
 await client.query('BEGIN');
 for(const file of ['database/functions/blueprint/canonical_metadata.sql','database/functions/blueprint/canonical_text_dependencies.sql','database/functions/blueprint/canonical_resource_projection.sql','database/functions/blueprint/image_assets.sql','database/functions/occasion_setup/blueprint_layout.sql','database/functions/occasion_setup/finalize.sql','database/functions/blueprint/canonical_validation.sql','database/functions/eshop/get_blueprint.sql','database/functions/eshop/get_blueprint_for_edit.sql','database/functions/others/duplicate_occasion.sql','database/functions/blueprint/save.sql'])await client.query(readFileSync(new URL(file,root),'utf8'));
 await client.query(readFileSync(new URL('database/tests/helpers/assertions.sql',root),'utf8'));
 await client.query(readFileSync(new URL('database/tests/blueprint/fixtures.sql',root),'utf8'));
 const f=(await client.query('SELECT public.blueprint_test_fixture_internal() f')).rows[0].f;
 await client.query("SELECT set_config('request.jwt.claim.sub',$1,true),set_config('request.jwt.claim.role','service_role',true)",[f.actor]);
 await client.query('SELECT public.register_blueprint_text_resources($1,NULL,$2)',[f.occasion,fixture.resources]);
 const descriptors=(await client.query('SELECT * FROM public.blueprint_layout_text_requests_internal($1,true)',[fixture.document])).rows;
 const expected=Object.values(fixture.resources.textLayouts).map(r=>r.descriptor);
 assert.equal(descriptors.length,expected.length);
 for(const row of descriptors)assert.ok(expected.some(d=>JSON.stringify(sort(d))===JSON.stringify(sort(row.descriptor))),'SQL and Dart requests must be identical');
 const unusedFamily=(await client.query("SELECT id FROM public.ticket_font_families WHERE NOT(id=ANY($1::text[])) ORDER BY id LIMIT 1",[Object.keys(fixture.resources.fontFamilies)])).rows[0].id;
 const declarationsOnly={...structuredClone(fixture.document),styles:{kinds:{shape:{label:{fontFamilyId:unusedFamily}}}}};
 const declaredResources=(await client.query('SELECT public.blueprint_canonical_text_resources_internal($1,$2,NULL,true) result',[declarationsOnly,f.occasion])).rows[0].result;
 assert.ok(declaredResources.fontFamilies[unusedFamily],'unused style family remains editable without preparing invented text');
 assert.deepEqual(Object.keys(declaredResources.textLayouts).sort(),Object.keys(fixture.resources.textLayouts).sort());
 const request={...f.request,layout:fixture.document,seatChanges:rowImport.document.nodes.filter(node=>node.kind==='seat').map(node=>({nodeId:node.id,title:node.label??'',productId:f.product,blocked:false,groupNodeId:null,selectionUnitId:fixture.document.selectionUnits.find(unit=>unit.nodeIds.includes(node.id))?.id??null,productAssignmentMode:'override',operation:'upsert'})),textResourceIds:Object.keys(fixture.resources.textLayouts).sort()};
 await client.query("SELECT set_config('request.jwt.claim.role','authenticated',true)");
 const saved=(await client.query('SELECT public.update_blueprint_client_sync_v1($1,gen_random_uuid()) result',[request])).rows[0].result;
 assert.equal(saved.status,'applied',JSON.stringify(saved));
 const read=async(sql,args)=>{const r=(await client.query(sql,args)).rows[0].result;assert.equal(r.code,200,JSON.stringify(r));const data=r.data;return {document:data.layout,resources:data.layoutResources};};
 const admin=await read('SELECT public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=$1)) result',[f.occasion]);
 const publicView=await read('SELECT public.get_blueprint(NULL,$1,$2) result',[f.formKey,f.blueprint]);
 assert.equal(Object.keys(admin.resources.textLayouts).length,expected.length);
 assert.equal(Object.keys(publicView.resources.textLayouts).length,expected.length-1);
 assert.equal(publicView.document.presets.length,0);
 assert.equal(admin.document.nodes.find(node=>node.kind==='vector').originalSource.text,vectorImport.node.originalSource.text);
 assert.ok(publicView.document.nodes.filter(node=>node.kind==='vector').every(node=>!Object.hasOwn(node,'originalSource')),'viewer contains converted vectors only');
 await client.query('SAVEPOINT original_source_guard');
 try {
  const invalid=structuredClone(fixture.document);invalid.nodes.find(node=>node.kind==='vector').originalSource.text+=' changed';
  await client.query('SELECT public.validate_blueprint_layout_internal($1)',[invalid]);
  assert.fail('changed original SVG requires its matching hash');
 } catch(error) { assert.equal(error.code,'23514');assert.match(error.message,/ORIGINAL_SOURCE/); }
 await client.query('ROLLBACK TO SAVEPOINT original_source_guard');
 await client.query('RELEASE SAVEPOINT original_source_guard');

 // Admission rejects malformed assembly counts and attachments before geometry projection.
 for(const [name,mutate,reason] of [
  ['fractional_rows',doc=>{doc.nodes.find(n=>n.assembly?.kind==='rows').assembly.rows=1.5;},/DECLARATION/],
  ['missing_row_spacing',doc=>{delete doc.nodes.find(n=>n.assembly?.kind==='rows').assembly.spacing;},/ASSEMBLY/],
  ['foreign_row_field',doc=>{doc.nodes.find(n=>n.assembly?.kind==='rows').assembly.left=2;},/DECLARATION/],
  ['row_on_wrong_kind',doc=>{doc.nodes.find(n=>n.assembly?.kind==='rows').kind='furniture';},/ASSEMBLY/],
  ['row_declared_capacity',doc=>{doc.nodes.find(n=>n.assembly?.kind==='rows').assembly.rows=1000000;},/ASSEMBLY_CAPACITY/],
  ['zero_row_spacing',doc=>{doc.nodes.find(n=>n.assembly?.kind==='rows').assembly.spacing=0;},/DECLARATION/],
  ['row_side_pin',doc=>{doc.attachments.find(a=>doc.nodes.find(n=>n.id===a.targetId)?.assembly?.kind==='rows').placement={mode:'sidePinned',side:'top',t:0.5};},/SIDE_PIN/],
  ['row_wrong_parent',doc=>{doc.nodes.find(n=>n.id===doc.attachments[0].seatId).parentId=null;},/ATTACHMENT/],
  ['duplicate_anchor',doc=>{doc.attachments.push(structuredClone(doc.attachments[0]));},/ATTACHMENT/],
 ]) {
  await client.query('SAVEPOINT assembly_guard');
  try {const invalid=structuredClone(fixture.document);mutate(invalid);await client.query('SELECT public.validate_blueprint_layout_internal($1)',[invalid]);assert.fail(name+' must fail admission');}
  catch(error){assert.equal(error.code,'23514',name);assert.match(error.message,reason,name);}
  await client.query('ROLLBACK TO SAVEPOINT assembly_guard');await client.query('RELEASE SAVEPOINT assembly_guard');
 }

 for(const [placement,accepted] of [
  [{mode:'sidePinned',cell:[0,0],face:'top'},true],
  [{mode:'sidePinned',cell:[1,0],face:'right'},false],
  [{mode:'sidePinned',cell:[3,0],face:'top'},false],
  [{mode:'sidePinned',side:'top',t:0.5},false],
 ]){
  const doc=structuredClone(fixture.document),table=doc.nodes.find(node=>node.kind==='table'),anchor=doc.attachments[0],seat=doc.nodes.find(node=>node.id===anchor.seatId);
  Object.assign(table,{width:120,height:80,surface:{type:'grid',moduleSize:40,outer:[[0,0],[3,0],[3,2],[0,2]],holes:[]}});
  seat.parentId=table.id;anchor.targetId=table.id;anchor.placement=placement;
  await client.query('SAVEPOINT grid_pin_guard');
  try{await client.query('SELECT public.validate_blueprint_layout_internal($1)',[doc]);assert.ok(accepted,'invalid grid pin must fail admission');}
  catch(error){assert.ok(!accepted,'valid boundary pin must be admitted');assert.equal(error.code,'23514');assert.match(error.message,/PIN/);}
  await client.query('ROLLBACK TO SAVEPOINT grid_pin_guard');await client.query('RELEASE SAVEPOINT grid_pin_guard');
 }

 const foreign=(await client.query('SELECT public.blueprint_test_fixture_internal() f')).rows[0].f;
 const foreignResources=(await client.query('SELECT public.blueprint_layout_resources_internal($1,$2) result',[fixture.document,foreign.occasion])).rows[0].result;
 assert.deepEqual(foreignResources.textLayouts,{});
 const changed=structuredClone(request);changed.expected_layout_revision=1;changed.layout.nodes[0].text+=' changed';
 const rejected=(await client.query('SELECT public.update_blueprint_client_sync_v1($1,gen_random_uuid()) result',[changed])).rows[0].result;
 assert.equal(rejected.data.reason,'BLUEPRINT_TEXT_RESOURCE_NOT_READY');
 await client.query('INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) SELECT unit,$2,true,true,true FROM public.occasions WHERE id=$1 ON CONFLICT DO NOTHING',[f.occasion,f.actor]);
 const copied=(await client.query('SELECT public.duplicate_occasion_internal_v1($1) id',[f.occasion])).rows[0].id;
 const bp=(await client.query('SELECT id FROM eshop.blueprints WHERE occasion=$1',[copied])).rows[0].id;
 await client.query('INSERT INTO public.occasion_users(occasion,"user",is_editor_order_view,is_editor,is_manager) VALUES($1,$2,true,true,true) ON CONFLICT DO NOTHING',[copied,f.actor]);
 const copy=await read('SELECT public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=$1)) result',[copied]);
 assert.equal(Object.keys(copy.resources.textLayouts).length,expected.length);
 assert.equal(copy.document.nodes.find(node=>node.kind==='vector').originalSource.text,vectorImport.node.originalSource.text);
 // A new setup owns prepared text in its private draft scope, then transfers
 // exactly those dependencies before invoking the aggregate materializer.
 const target=(await client.query('SELECT public.blueprint_test_fixture_internal() f')).rows[0].f;
 const targetScope=(await client.query('SELECT unit,organization FROM public.occasions WHERE id=$1',[target.occasion])).rows[0];
 await client.query('INSERT INTO public.unit_users(unit,"user",is_manager,is_editor,is_editor_view) VALUES($1,$2,true,true,true) ON CONFLICT DO NOTHING',[targetScope.unit,f.actor]);
 const setupDocument=structuredClone(fixture.document),hash='b'.repeat(64),assetRef=`image:${hash}`;
 setupDocument.nodes.push({id:'20000000-0000-4000-8000-000000000099',kind:'image',width:80,height:40,transform:{x:1200,y:700,rotation:0},graphic:{type:'bitmap',assetRef,hash,crop:{x:0,y:0,width:1,height:1}}});
 const setupPlan={layout:setupDocument,seatBindings:rowImport.document.nodes.filter(node=>node.kind==='seat').map(node=>({nodeId:node.id,title:node.label??'',productId:f.product,blocked:false,groupNodeId:null,selectionUnitId:fixture.document.selectionUnits.find(unit=>unit.nodeIds.includes(node.id))?.id??null,productAssignmentMode:'override'})),groupProducts:[],areaBindings:[]};
 const draft=(await client.query('INSERT INTO public.occasion_setup_drafts(id,unit,organization,author,data) VALUES(gen_random_uuid(),$1,$2,$3,$4) RETURNING id',[targetScope.unit,targetScope.organization,f.actor,{blueprintLayoutDraft:setupPlan}])).rows[0].id;
 await client.query("SELECT set_config('request.jwt.claim.role','service_role',true)");
 await client.query('SELECT public.register_blueprint_text_resources(NULL,$1,$2)',[draft,fixture.resources]);
 await client.query("INSERT INTO public.blueprint_image_assets(unit,organization,asset_ref,hash,url,width,height,mime_type,byte_length,state) VALUES($1,$2,$3,$4,$5,80,40,'image/png',100,'ready')",[targetScope.unit,targetScope.organization,assetRef,hash,'https://images.example.invalid/canonical-setup.png']);
 await client.query("SELECT set_config('request.jwt.claim.role','authenticated',true)");
 const setupResources=(await client.query('SELECT public.get_occasion_setup_blueprint_resources($1) result',[draft])).rows[0].result.resources;
 assert.equal(Object.keys(setupResources.textLayouts).length,expected.length);
 assert.ok(setupResources.assets[assetRef],'setup image nodes use the verified unit manifest');
 const unavailable=(await client.query('SELECT public.blueprint_canonical_text_resources_internal($1,$2,NULL,true) result',[setupDocument,target.occasion])).rows[0].result;
 assert.deepEqual(unavailable.textLayouts,{});
 await client.query('UPDATE public.forms SET blueprint=NULL WHERE id=$1',[target.form]);
 await client.query('DELETE FROM eshop.blueprints WHERE id=$1',[target.blueprint]);
 await client.query('SELECT public.copy_blueprint_text_resources_internal(NULL,$1,$2,$3)',[draft,target.occasion,setupDocument]);
 const materialized=(await client.query('SELECT public.materialize_setup_blueprint_layout_internal($1,$2,NULL,$3,$4) id',[setupPlan,{[f.product]:target.product},target.occasion,targetScope.unit])).rows[0].id;
 assert.ok(materialized);
 await client.query('UPDATE public.forms SET blueprint=$1 WHERE id=$2',[materialized,target.form]);
 const setup=await read('SELECT public.get_blueprint_for_edit((SELECT link FROM public.occasions WHERE id=$1)) result',[target.occasion]);
 assert.equal(Object.keys(setup.resources.textLayouts).length,expected.length);
 assert.ok(setup.resources.assets[assetRef],'materialization transfers bitmap object manifests');
 for(const file of ['database/tests/blueprint/layout_integration_test.sql','database/tests/blueprint/copy_setup_test.sql','database/tests/blueprint/canonical_text_resources_test.sql'])await client.query(readFileSync(new URL(file,root),'utf8'));
 writeFileSync(new URL('test/fixtures/blueprint/canonical-text-sql-roundtrip.json',root),JSON.stringify({admin,public:publicView,copy,setup},null,2)+'\n');
 console.log('Canonical SQL save/read/copy/setup: exact Dart descriptors, private projections, scope isolation, stale preparation rejection and bitmap manifest transfer pass; rolled back.');
}finally{await client.query('ROLLBACK');await client.end();}
function sort(v){return Array.isArray(v)?v.map(sort):v&&typeof v==='object'?Object.fromEntries(Object.entries(v).sort(([a],[b])=>a<b?-1:a>b?1:0).map(([k,x])=>[k,sort(x)])):v;}
