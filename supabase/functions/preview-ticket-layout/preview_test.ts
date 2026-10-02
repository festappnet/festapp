import {assertEquals,assert} from 'jsr:@std/assert@1';
import {handlePreview,type PreviewDependencies} from './handler.ts';
import {fontBytes,fontMetrics} from '../_shared/ticketGeneration.ts';
import {preset} from '../_shared/ticketLayout.ts';
import {sampleData, type PreviewProduct} from '../_shared/ticketRenderData.ts';
import {formatCurrency} from '../_shared/utilities.ts';
const font=await fontBytes();const metrics=fontMetrics(font);
const body={occasionId:7,mode:'resolve',type:'named'};
const req=(value:unknown=body,auth=true)=>new Request('https://test.invalid',{method:'POST',headers:auth?{Authorization:'Bearer test'}:{},body:JSON.stringify(value)});
const offered:PreviewProduct[]=[
  {id:30,type:'food',title:'Kuřecí řízek s bramborem',data:{short_title:'Řízek'},price:170,currency_code:'CZK'},
  {id:20,type:'spot',title:'Vstupenka',price:450,currency_code:'CZK'},
  {id:10,type:'spot',title:'Skrytá vstupenka',price:1,currency_code:'CZK',is_hidden:true},
  {id:40,type:'food',title:'Jiná večeře',price:200,currency_code:'CZK'},
];
Deno.test('preview samples use deterministic offered products, short titles and their combined real price',()=>{
  const data=sampleData('normal',undefined,offered);
  assertEquals(data.food,'Večeře: Řízek');
  assertEquals(data.price,`Cena: ${formatCurrency(620,'CZK')}`);
  assertEquals(sampleData('normal',undefined,[...offered].reverse()),data);
  assert(data.qr!.startsWith('festapp-preview:'));
  assertEquals(sampleData('missing',undefined,offered).food,null);
  assertEquals(sampleData('long',undefined,offered).price,data.price);
});
Deno.test('preview samples keep zero prices, respect currency and omit unavailable food',()=>{
  const ticket={id:1,type:'spot',title:'Vstupenka zdarma',price:0,currency_code:'EUR'};
  const data=sampleData('normal',undefined,[ticket,...offered.filter(p=>p.type==='food')]);
  assertEquals(data.price,`Cena: ${formatCurrency(0,'EUR')}`);
  assertEquals(data.food,null);
  const foodOnly=sampleData('normal',undefined,[offered[0]]);
  assertEquals(foodOnly.price,`Cena: ${formatCurrency(170,'CZK')}`);
  assertEquals(foodOnly.food,'Večeře: Řízek');
});
Deno.test('preview samples fall back when the offer is empty or has no usable products',()=>{
  const fallback=sampleData();
  assertEquals(sampleData('normal',undefined,[]),fallback);
  assertEquals(sampleData('normal',undefined,[
    {...offered[0],is_hidden:true},{...offered[1],price:NaN},
    {...offered[1],price:-10},{...offered[1],title:' '},
  ]),fallback);
});
Deno.test('resolve loads only the authorized occasion offer once for every sample scenario',async()=>{
  const s=setup();const ids:number[]=[];
  s.deps.products=async id=>{ids.push(id);return offered;};
  const response=await handlePreview(req(),s.deps);
  assertEquals(response.status,200);
  const result=await response.json();
  assertEquals(ids,[7]);
  assertEquals(result.data.food,'Večeře: Řízek');
  for(const scenario of Object.values(result.scenarios) as any[]) {
    assertEquals(scenario.price,`Cena: ${formatCurrency(620,'CZK')}`);
  }
});
Deno.test('offer read errors reject the preview instead of silently inventing a catalog',async()=>{
  const s=setup();s.deps.products=async()=>{throw new Error('database unavailable');};
  assertEquals((await handlePreview(req(),s.deps)).status,400);
});
function setup(allowed=true){let reads=0,resources=0,products=0;const deps:PreviewDependencies={authorize:async()=>allowed,occasion:async()=>{reads++;return {id:7,features:[{code:'ticket',ticket_type:'named'}],data:{}};},products:async()=>{products++;return [];},resources:async()=>{resources++;return {font,metrics};}};return {deps,counts:()=>[reads,resources,products]};}
Deno.test('preview rejects unauthenticated and foreign unit before resource reads',async()=>{
  const s=setup(false);assertEquals((await handlePreview(req(body,false),s.deps)).status,401);assertEquals((await handlePreview(req(),s.deps)).status,403);assertEquals(s.counts(),[0,0,0]);
});
Deno.test('resolve returns an editable preset and font metrics without rendering PDF',async()=>{
  const s=setup();const response=await handlePreview(req(),s.deps);assertEquals(response.status,200);const result=await response.json();assertEquals(result.template.font,'roboto');assertEquals(result.template.page,{width:212.5,height:387.5});assertEquals(result.metrics,metrics);assertEquals(result.file,undefined);assertEquals(s.counts(),[1,1,1]);
});
Deno.test('only explicit pdf produces sample bytes',async()=>{
  const s=setup();const response=await handlePreview(req({...body,mode:'pdf',layout:{schemaVersion:1,templates:{named:preset('named')}}}),s.deps);assertEquals(response.status,200);const result=await response.json();assert(atob(result.file).startsWith('%PDF'));assertEquals(s.counts(),[1,1,1]);
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
    assertEquals(result.template.font,type==='named'?'roboto':'futura');
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

Deno.test('portrait artwork cannot turn landscape gallery templates into portrait tickets',async()=>{
 const s=setup();
 const blank=await (await handlePreview(req({...body,type:'wide'}),s.deps)).json();
 const background=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAIAAAAGCAIAAABmRdhlAAAADklEQVR4nGP4DwYMhCkA8VQj3S7lL6QAAAAASUVORK5CYII='),c=>c.charCodeAt(0));
 s.deps.resources=async()=>({font,metrics,background});
 const withImage=await (await handlePreview(req({...body,type:'wide'}),s.deps)).json();
 for(const key of ['classic','compact','event']) {
   const t=withImage.presets[key];
   assert(t.ticketArea.width>t.ticketArea.height,`${key} must stay landscape`);
   assertEquals(t,blank.presets[key]);
   assertEquals(t.page,{width:595.28,height:841.89});
 }
 for(const key of ['portrait','portrait_compact','portrait_event']) {
   const t=withImage.presets[key];assert(t.ticketArea.height>t.ticketArea.width);
 }
 assertEquals(withImage.background,btoa(String.fromCharCode(...background)));
});

Deno.test('deleted background resolves for repair but never silently renders PDF',async()=>{
  const {loadLayoutResources}=await import('../_shared/ticketGeneration.ts');
  const {UnsafeTargetError}=await import('../fetch-http-data/safeFetch.ts');
  const occasion={id:13,organization:3,features:[{code:'ticket',ticket_type:'wide',background:'https://img.festapp.net/editor/skautskyples2025.jpeg'}]};
  const missing=async()=>{throw new UnsafeTargetError('upstream_404');};
  const deps:PreviewDependencies={authorize:async()=>true,occasion:async()=>occasion,products:async()=>[],
    resources:(o,f,options)=>loadLayoutResources(o,f,options,missing)};
  const input={occasionId:13,mode:'resolve',type:'wide'};
  const response=await handlePreview(req(input),deps);
  assertEquals(response.status,200);
  const resolved=await response.json();
  assertEquals(resolved.missingBackground,true);
  assertEquals(resolved.background,null);
  assertEquals(resolved.backgroundUrl,occasion.features[0].background);
  assert(resolved.template.elements.some((e:any)=>e.binding==='qr'));
  assertEquals((await handlePreview(req({...input,mode:'pdf'}),deps)).status,400);
  let rejected=false;
  try {await loadLayoutResources(occasion,undefined,{},missing);} catch {rejected=true;}
  assert(rejected,'production renderer remains strict');
  for(const error of ['unsafe_target','upstream_403','upstream_500','invalid_content_type']) {
    deps.resources=(o,f,options)=>loadLayoutResources(o,f,options,async()=>{throw new UnsafeTargetError(error);});
    assertEquals((await handlePreview(req(input),deps)).status,400,error);
  }
});
