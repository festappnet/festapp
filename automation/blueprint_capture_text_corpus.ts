/** Local-only shared fixture: core-derived requests, actual registered bytes,
 * prepared whole paragraphs. No credentials, mutations or remote font fallback.
 * deno run --allow-read --allow-write=test/fixtures/blueprint,supabase/.temp/blueprint-typography --allow-run=fvm automation/blueprint_capture_text_corpus.ts
 */
import {fontFamilyCatalog,fontCatalog,fontMetrics} from '../supabase/functions/_shared/ticketFonts.ts';
import {prepareLayoutTextResources} from '../supabase/functions/_shared/layoutTextResources.ts';
const root=new URL('../',import.meta.url),core='/Users/miakh/source/venue-seat-picker-blueprint-b-20261019/packages/venue_layout_core';
const proof=JSON.parse(await Deno.readTextFile(new URL('docs/plans/evidence/blueprint-typography-20261020/engine-probe.json',root)));
const families=Object.fromEntries(fontFamilyCatalog.map(f=>[f.id,f]));
const nodes=proof.preparation.map((p:any,i:number)=>{
 const family=fontFamilyCatalog.find(f=>Object.values(f.faces).includes(p.fontId))!;
 return {id:`20000000-0000-4000-8000-${String(i+1).padStart(12,'0')}`,kind:'text',text:p.text,
  transform:{x:200+i*260,y:180,rotation:i===1?17:0},width:180,height:300,
  style:{label:{fontFamilyId:family.id,size:28,language:p.result.descriptor.request.language,direction:p.result.descriptor.request.direction,weight:400,italic:false}}};
});
const roboto=fontFamilyCatalog.find(f=>f.family==='Roboto')!;
nodes.push({id:'20000000-0000-4000-8000-000000000050',kind:'table',label:'Příliš široký název stolu',transform:{x:400,y:600,rotation:23},width:220,height:80,surface:{type:'rect'},style:{label:{fontFamilyId:roboto.id,size:28}}});
const preset={id:'20000000-0000-4000-8000-000000000060',title:'Admin only',document:{schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1000,height:600,fill:'#ffffffff'},styles:{label:{fontFamilyId:roboto.id}},seatingDefaults:{},textPolicy:{language:'und',direction:'auto'},nodes:[{id:'20000000-0000-4000-8000-000000000061',kind:'text',text:'Private preset text',width:240,height:80,transform:{x:200,y:200,rotation:0}}]}};
const document={schemaVersion:2,symbolSetVersion:1,canvas:{x:0,y:0,width:1400,height:800,fill:'#ffffffff'},styles:{},seatingDefaults:{},textPolicy:{language:'und',direction:'auto'},nodes,sections:[],selectionUnits:[],attachments:[],presets:[preset]};
const input=new URL('supabase/.temp/blueprint-typography/canonical-request-input.json',root),output=new URL('supabase/.temp/blueprint-typography/canonical-request-output.json',root);
await Deno.writeTextFile(input,JSON.stringify({document,families}));
const result=await new Deno.Command('fvm',{cwd:core,args:['dart','tool/parity_fixture.dart','--text-requests',input.pathname,output.pathname],stdout:'piped',stderr:'piped'}).output();
if(!result.success)throw Error(new TextDecoder().decode(result.stderr));
const batch=JSON.parse(await Deno.readTextFile(output));
const resources=await prepareLayoutTextResources(batch,async id=>{
 const asset=fontCatalog.find(f=>f.id===id)!;
 const bytes=await Deno.readFile(new URL(`supabase/.temp/blueprint-typography/${asset.sha256}.ttf`,root));
 return {...asset,bytes,metrics:fontMetrics(bytes)};
});
await Deno.writeTextFile(new URL('test/fixtures/blueprint/canonical-text-scene.json',root),JSON.stringify({document,requests:batch,resources},null,2)+'\n');
console.log(`Canonical paragraph fixture: ${nodes.length} texts, ${Object.keys(resources.fontFamilies).length} families, requests derived by Dart core.`);
