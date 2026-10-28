import { loadToken, createSdk, evidenceWriter, evidenceDirectory, runInactiveScenario, cleanSourceRevision, safeFailure, assertReviewerContext, ensureScenariosInactive, assertReviewerFixture } from './lib/make-sdk.mjs';
import{readFile}from'node:fs/promises';
import{homedir}from'node:os';
import{createHash}from'node:crypto';
import assert from'node:assert/strict';
assert(process.argv.includes('--apply'),'Use --apply to run the two existing on-demand qualification scenarios. Never creates scenarios or reviews.');
const root=new URL('../',import.meta.url),app=JSON.parse(await readFile(new URL('app.json',root),'utf8'));
const sourceRevision=cleanSourceRevision(root);
const {assemble,writeGenerated}=await import('./build.mjs');await writeGenerated(await assemble(),{check:true});
assert.equal(app.organizationId,9450617);assert.equal(app.teamId,3387186);
const context=JSON.parse(await readFile(new URL('src/reviewer.json',root),'utf8'));
const scenarioIds=[context.positiveScenarioId,context.guardrailsScenarioId];
const request=createSdk(app,await loadToken());
const module=(id,name,mapper)=>({id,module:'app#'+app.name+':'+name,version:app.version,parameters:{__IMTCONN__:context.connectionId},mapper,metadata:{designer:{x:id*200,y:id*80}}});
const receipt={at:new Date().toISOString(),app:app.name,version:app.version,zone:app.zone,generatedManifestSha256:createHash('sha256').update(await readFile(new URL('src/generated/manifest.json',root))).digest('hex'),positive:null,cases:[],bothScenariosInactive:false};
const checkpoint=evidenceWriter(evidenceDirectory(),'qualification',{sourceRevision,freeze:context.freeze});
const save=()=>checkpoint(receipt);
let preflightComplete=false;
try {
const demo=JSON.parse(await readFile(homedir()+'/'+context.fixtureReceipt,'utf8'));
const expected=JSON.parse(await readFile(new URL('review/demo-data.json',root),'utf8'));
assertReviewerFixture(demo,expected,context.fixtureMarker);
const event=demo.occasionIds[0],order=demo.orders.find(o=>o.occasionId===event).id;
const positive={name:'vstupenky.online qualification',flow:[module(1,'salesReport',{occasionId:event}),{id:2,module:'builtin:BasicRouter',version:1,mapper:null,metadata:{designer:{x:250,y:0}},routes:[
 {flow:[module(3,'listOccasions',{limit:10}),module(7,'apiCall',{url:'/make/v1/operations/orders.list',method:'POST',body:'{"occasionId":{{if(3.capabilities.`ticket_layouts.read` = false; '+event+'; 0)}},"limit":1}'})]},
 {flow:[module(4,'listOrders',{occasionId:event,limit:52})]},
 {flow:[module(5,'getOrder',{occasionId:event,orderId:order})]},
 {flow:[module(6,'apiCall',{url:'/make/v1/operations/orders.list',method:'POST',body:'{"occasionId":'+event+',"search":"{{formatDate(1.report.generated_at; "YYYYMMDDHH")}}","limit":1}'})]}
 ]}],metadata:{version:1,scenario:{roundtrips:1,maxErrors:1,sequential:true},designer:{orphans:[]},zone:app.zone}};
const setBlueprint=async(id,blueprint)=>{const previous=(await request('/scenarios/'+id+'/blueprint')).response;await request('/scenarios/'+id,'PATCH',{blueprint:JSON.stringify(blueprint),baseVersion:previous.version,scheduling:JSON.stringify({type:'on-demand'})});};
const run=id=>runInactiveScenario(request,id);
await assertReviewerContext(request,app,context);preflightComplete=true;
await setBlueprint(context.positiveScenarioId,positive);const result=await run(context.positiveScenarioId);receipt.positive={scenarioId:context.positiveScenarioId,...result,modules:[]};await save();assert.equal(result.status,1,'all five modules and mapping consumers must succeed');
for(const [id,bundles]of [[1,1],[3,1],[4,52],[5,1],[6,1],[7,1]]){const log=(await request('/scenarios/'+context.positiveScenarioId+'/modules/'+id+'/logs?pg[limit]=5')).moduleLogs.find(x=>x.executionId===result.executionId);assert.equal(log?.bundles,bundles,'module '+id);receipt.positive.modules.push({id,bundles:log.bundles,status:log.status});}
receipt.positive.mappingProofs=['The literal dotted capability key is consumed with backticks by module 7 and must be false for the read-only fixture; undefined or wrong mapping would select invalid event ID 0.','The parsed report timestamp is consumed by formatDate in module 6 and supplied as an exact 10-character symbol search.'];await save();console.log('PASS: all five modules, 52 orders over two pages, date consumer and literal dotted-key consumer.');
const apiContext={url:'/make/v1/operations/context.inspect',method:'POST',body:'{}'};
const cases=[
 ['reserved_header_overrides_ignored','apiCall',{...apiContext,qs:[{key:'qualification',value:'review'}],headers:[{key:'aUtHoRiZaTiOn',value:'Bearer invalid'},{key:'Authorization',value:'Bearer invalid'},{key:'Host',value:'example.invalid'},{key:'X-Festapp-Make-Page',value:'51'},{key:'Accept',value:'application/json'}]},null],
 ['unsupported_method','apiCall',{...apiContext,method:'PUT'},/405/],
 ['unknown_operation','apiCall',{...apiContext,url:'/make/v1/operations/unknown'},/403/],
 ['write_operation_rejected','apiCall',{...apiContext,url:'/make/v1/operations/orders.cancel'},/403/],
 ['unconsented_order_detail','getOrder',{occasionId:demo.occasionIds[1],orderId:demo.orders.find(o=>o.occasionId===demo.occasionIds[1]).id},/403/],
 ['foreign_url_rejected','apiCall',{...apiContext,url:'https://example.invalid/forbidden'},/403/]
];
for(const [name,key,mapper,error]of cases){await setBlueprint(context.guardrailsScenarioId,{...positive,name:'vstupenky.online guardrails',flow:[module(1,key,mapper)]});const result=await run(context.guardrailsScenarioId);receipt.cases.push({name,scenarioId:context.guardrailsScenarioId,...result});await save();assert.equal(result.status,error?3:1,name);if(error)assert.match(result.error?.message??'',error,name);console.log('PASS: '+name);}
const final=(await request('/scenarios?teamId='+app.teamId)).scenarios;assert(final.filter(s=>scenarioIds.includes(s.id)).every(s=>!s.isActive));receipt.bothScenariosInactive=true;await save();console.log('PASS: both scenarios inactive; no external destination writes or new review request.');

receipt.status='qualified';
} catch(error) { receipt.status='failed';receipt.error=safeFailure(error);throw error; }
finally {
 if(preflightComplete)Object.assign(receipt,await ensureScenariosInactive(request,scenarioIds));
 await save();
 if(preflightComplete)assert(!receipt.cleanupFailures.length && receipt.bothScenariosInactive,'Scenario cleanup failed; inspect recorded evidence');
}
