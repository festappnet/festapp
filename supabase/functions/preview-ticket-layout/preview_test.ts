import {assertEquals,assert} from 'jsr:@std/assert@1';
import {handlePreview,type PreviewDependencies} from './handler.ts';
import {fontBytes,fontMetrics} from '../_shared/ticketGeneration.ts';
import {preset} from '../_shared/ticketLayout.ts';
const font=await fontBytes();const metrics=fontMetrics(font);
const body={occasionId:7,mode:'resolve',type:'named'};
const req=(value:unknown=body,auth=true)=>new Request('https://test.invalid',{method:'POST',headers:auth?{Authorization:'Bearer test'}:{},body:JSON.stringify(value)});
function setup(allowed=true){let reads=0,resources=0;const deps:PreviewDependencies={authorize:async()=>allowed,occasion:async()=>{reads++;return {id:7,features:[{code:'ticket',ticket_type:'named'}],data:{}};},resources:async()=>{resources++;return {font,metrics};}};return {deps,counts:()=>[reads,resources]};}
Deno.test('preview rejects unauthenticated and foreign unit before resource reads',async()=>{
  const s=setup(false);assertEquals((await handlePreview(req(body,false),s.deps)).status,401);assertEquals((await handlePreview(req(),s.deps)).status,403);assertEquals(s.counts(),[0,0]);
});
Deno.test('resolve returns an editable preset and font metrics without rendering PDF',async()=>{
  const s=setup();const response=await handlePreview(req(),s.deps);assertEquals(response.status,200);const result=await response.json();assertEquals(result.template,preset('named'));assertEquals(result.metrics,metrics);assertEquals(result.file,undefined);assertEquals(s.counts(),[1,1]);
});
Deno.test('only explicit pdf produces sample bytes',async()=>{
  const s=setup();const response=await handlePreview(req({...body,mode:'pdf',layout:{schemaVersion:1,templates:{named:preset('named')}}}),s.deps);assertEquals(response.status,200);const result=await response.json();assert(atob(result.file).startsWith('%PDF'));assertEquals(s.counts(),[1,1]);
});
Deno.test('preview bounds input and rejects secrets, real IDs and unapproved image sources',async()=>{
  for(const value of [{...body,requestSecret:'system'},{...body,ticketId:1},{...body,background:'https://localhost/image'},{...body,mode:'auto'},{...body,layout:{schemaVersion:2}},{...body,large:'x'.repeat(50000)}]){
    const s=setup();const status=(await handlePreview(req(value),s.deps)).status;assert([400,413].includes(status));
  }
});
Deno.test('resolve returns style choices and uses known occasion details in every scenario',async()=>{
  const s=setup();s.deps.occasion=async()=>({id:7,title:'Festival v naší obci',start_time:'2026-11-07T18:00:00Z',end_time:'2026-11-07T23:00:00Z',data:{place_name:'Sokolovna'},features:[]});
  const result=await (await handlePreview(req(),s.deps)).json();
  assertEquals(Object.keys(result.presets),['classic','compact','event','portrait','portrait_compact','portrait_event']);
  for(const scenario of Object.values(result.scenarios) as any[]) {assertEquals(scenario.occasionTitle,'Festival v naší obci');assert(scenario.occasionDatePlace.includes('Sokolovna'));assert(scenario.occasionDatePlace.includes('11. 2026'));assertEquals(scenario.qr,'festapp-preview:X3827K6M8R');}
});
Deno.test('image-backed presets inherit existing text color without weakening QR colors',async()=>{
  const s=setup();s.deps.occasion=async()=>({id:7,title:'Ples',features:[{code:'ticket',darkColor:'FFFFFF'}]});
  const png=await Deno.readFile('test/fixtures/ticket_layout/background.png');s.deps.resources=async()=>({font,metrics,background:png});
  const result=await (await handlePreview(req({...body,type:'wide'}),s.deps)).json();
  assertEquals(result.template.elements.find((e:any)=>e.binding==='price').style.color,'FFFFFF');
  assertEquals(result.template.elements.find((e:any)=>e.binding==='qr').style.color,'2A2A2A');
});

Deno.test('portrait PDF page matches editable ticket area',async()=>{
  const s=setup();
  const choices=await (await handlePreview(req({...body,type:'wide'}),s.deps)).json();
  assertEquals(choices.presetBackgrounds.portrait,null);
  const t=choices.presets.portrait;
  assert(t.ticketArea.height>t.ticketArea.width);
  t.ticketArea.width=240; t.ticketArea.height=450; t.page={width:240,height:450};
  const response=await handlePreview(req({...body,type:'wide',mode:'pdf',background:null,layout:{schemaVersion:1,templates:{wide:t}}}),s.deps);
  assertEquals(response.status,200);
  const {PDFDocument}=await import('npm:pdf-lib');
  const doc=await PDFDocument.load(Uint8Array.from(atob((await response.json()).file),c=>c.charCodeAt(0)));
  assertEquals(doc.getPages()[0].getSize(),{width:240,height:450});
});

Deno.test('legacy type does not restrict gallery, background selection or saved layout',async()=>{
  const s=setup();
  const results=[];
  for(const type of ['named','wide']) {
    const response=await handlePreview(req({...body,type}),s.deps);
    const result=await response.json();results.push(result);
    assertEquals(result.template,preset(type as 'named'|'wide',1600,900));
    const template=result.presets.compact;
    const background='https://img.festapp.net/custom-ticket.png';
    let received:any;
    s.deps.resources=async(_occasion,feature)=>{received=feature;return {font,metrics};};
    const reopened=await handlePreview(req({...body,type,background,layout:{schemaVersion:1,templates:{[type]:template}}}),s.deps);
    assertEquals(reopened.status,200);
    assertEquals((await reopened.json()).template,template);
    assertEquals(received.background,background);
  }
  assertEquals(results[0].presets,results[1].presets);
  assertEquals(results[0].presetBackgrounds,results[1].presetBackgrounds);
});

Deno.test('an unchanged saved background remains usable when it predates img.festapp.net',async()=>{
  const s=setup();
  const background='https://legacy-example.supabase.co/storage/v1/object/public/tickets/ball.png';
  s.deps.occasion=async()=>({id:7,features:[{code:'ticket',ticket_type:'wide',background}]});
  const response=await handlePreview(req({...body,type:'wide',background}),s.deps);
  assertEquals(response.status,200);
});

Deno.test('conference2024 empty stored background resolves without parsing an empty URL',async()=>{
  const s=setup();
  s.deps.occasion=async()=>({id:1,organization:1,features:[{code:'ticket',background:''}]});
  const response=await handlePreview(req({...body,occasionId:1,type:'wide',background:''}),s.deps);
  assertEquals(response.status,200);
  assertEquals((await response.json()).backgroundUrl,null);
});
