import type {PDFDict as PDFDictType, PDFRawStream as PDFRawStreamType} from 'npm:pdf-lib';
import {futuraId,fontMetrics} from '../_shared/ticketFonts.ts';
import {assertEquals,assert} from 'jsr:@std/assert@1';
import {handlePreview,type PreviewDependencies} from './handler.ts';
import {preset} from '../_shared/ticketLayout.ts';
import {sampleData, type PreviewProduct} from '../_shared/ticketRenderData.ts';
import {formatCurrency} from '../_shared/utilities.ts';
const font=await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');const metrics=fontMetrics(font);
const body={occasionId:7,mode:'resolve',type:'named',fontProtocol:2};
const admission={abuseLimits:{'document.input.bytes':1048576,'document.asset.bytes':5242880,'document.output.bytes':16777216,'document.output.pages':20}};
const req=(value:unknown=body,auth=true)=>new Request('https://test.invalid',{method:'POST',headers:auth?{Authorization:'Bearer test'}:{},body:JSON.stringify(value)});
function setup(allowed=true){let reads=0,resources=0,products=0;const deps:PreviewDependencies={authorize:async()=>allowed?admission:false,occasion:async()=>{reads++;return {id:7,features:[{code:'ticket',ticket_type:'named'}],data:{}};},products:async()=>{products++;return {types:new Map(),products:new Map()};},resources:async()=>{resources++;return {font,metrics,fonts:{[futuraId]:{id:futuraId,bytes:font,metrics,family:'Futura PT',weight:400}}};}};return {deps,counts:()=>[reads,resources,products]};}
Deno.test('preview rejects unauthenticated and foreign unit before resource reads',async()=>{
  const s=setup(false);assertEquals((await handlePreview(req(body,false),s.deps)).status,401);assertEquals((await handlePreview(req(),s.deps)).status,403);assertEquals(s.counts(),[0,0,0]);
});
Deno.test('resolve returns an editable preset and font metrics without rendering PDF',async()=>{
  const s=setup();const response=await handlePreview(req(),s.deps);assertEquals(response.status,200);const result=await response.json();assertEquals(result.template.page,{width:595.28,height:841.89});assertEquals(result.metrics,metrics);assertEquals(result.file,undefined);assertEquals(s.counts(),[1,1,1]);
});
Deno.test('only explicit pdf produces sample bytes',async()=>{
  const s=setup();const response=await handlePreview(req({...body,mode:'pdf',layout:{schemaVersion:3,templates:{named:preset('named')}}}),s.deps);assertEquals(response.status,200);const result=await response.json();assert(atob(result.file).startsWith('%PDF'));assertEquals(s.counts(),[1,1,1]);
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
  assertEquals(result.template.elements.find((e:any)=>e.binding==='qr').style.color,'000000');
});

Deno.test('portrait PDF page includes the default margin after resizing',async()=>{
  const s=setup();
  const choices=await (await handlePreview(req({...body,type:'wide'}),s.deps)).json();
  assertEquals(choices.presetBackgrounds.portrait,null);
  const t=choices.presets.portrait;
  assert(t.ticketArea.height>t.ticketArea.width);
  t.ticketArea.width=240; t.ticketArea.height=450; t.page={width:240+2*t.pageMargin,height:450+2*t.pageMargin};
  const response=await handlePreview(req({...body,type:'wide',mode:'pdf',background:null,layout:{schemaVersion:3,templates:{wide:t}}}),s.deps);
  assertEquals(response.status,200);
  const {PDFDocument}=await import('npm:pdf-lib');
  const doc=await PDFDocument.load(Uint8Array.from(atob((await response.json()).file),c=>c.charCodeAt(0)));
  assertEquals(t.pageMargin,3*72/25.4);
  assertEquals(doc.getPages()[0].getSize(),t.page);
});

Deno.test('legacy type does not restrict gallery, background selection or saved layout',async()=>{
  const s=setup();
  const results=[];
  for(const type of ['named','wide']) {
    const response=await handlePreview(req({...body,type}),s.deps);
    const result=await response.json();results.push(result);
    assertEquals(result.template.font,undefined);
    const template=result.presets.compact;
    const background='https://img.festapp.net/custom-ticket.png';
    let received:any;
    s.deps.resources=async(_occasion,feature)=>{received=feature;return {font,metrics,fonts:{[futuraId]:{id:futuraId,bytes:font,metrics,family:'Futura PT',weight:400}}};};
    const reopened=await handlePreview(req({...body,type,background,layout:{schemaVersion:3,templates:{[type]:template}}}),s.deps);
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
  s.deps.occasion=async()=>({id:7,features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:3,templates:{wide:preset('wide')}},background}]});
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
  const occasion={id:13,organization:3,features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:3,templates:{wide:preset('wide')}},background:'https://img.festapp.net/editor/skautskyples2025.jpeg'}]};
  const missing=async()=>{throw new UnsafeTargetError('upstream_404');};
  const deps:PreviewDependencies={authorize:async()=>admission,occasion:async()=>occasion,products:async()=>({types:new Map(),products:new Map()}),
    resources:(o,f,options)=>loadLayoutResources(o,f,options,missing)};
  const input={occasionId:13,mode:'resolve',type:'wide',fontProtocol:2};
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

Deno.test('font mode authorizes before resolver, does not load images or occasion, and returns safe error code',async()=>{
 const {futuraId,TicketFontError}=await import('../_shared/ticketFonts.ts');
 const s=setup(false);let loads=0;s.deps.font=async()=>{loads++;return {id:futuraId,bytes:font,metrics,family:'Futura PT',weight:400};};
 const request={occasionId:7,mode:'font',fontProtocol:2,fontId:futuraId};
 assertEquals((await handlePreview(req(request),s.deps)).status,403);assertEquals(loads,0);
 s.deps.authorize=async()=>admission;assertEquals((await handlePreview(req(request),s.deps)).status,200);assertEquals(s.counts(),[0,0,0]);assertEquals(loads,1);
 s.deps.font=async()=>{throw new TicketFontError('font_storage_read');};
 assertEquals(await (await handlePreview(req(request),s.deps)).json(),{error:'font_storage_read'});
});
Deno.test('schema 3 requires font protocol 2; invalid draft is rejected before loading, selected draft owns resources',async()=>{
 const {futuraId}=await import('../_shared/ticketFonts.ts');const s=setup();const t={...preset('named'),fontId:futuraId};
 const layout={schemaVersion:3,templates:{named:t}};
 assertEquals((await handlePreview(req({...body,fontProtocol:undefined,layout}),s.deps)).status,400);assertEquals(s.counts(),[1,0,1]);
 let captured:any;s.deps.resources=async(_occasion,feature)=>{captured=feature.layout.templates.named;assertEquals(feature.layout,layout);return {font,metrics,fonts:{[futuraId]:{id:futuraId,bytes:font,metrics,family:'Futura PT',weight:400}}};};
 const response=await handlePreview(req({...body,fontProtocol:2,layout}),s.deps);assertEquals(response.status,200);assertEquals(captured,t);const result=await response.json();assertEquals(result.fonts[futuraId].font,(await import('node:buffer')).Buffer.from(font).toString('base64'));
});
Deno.test('warm font cache never skips authorization',async()=>{
 const {futuraId,TicketFontResolver}=await import('../_shared/ticketFonts.ts');let bundled=0;
 const resolver=new TicketFontResolver({fetch:async()=>{throw Error('network');},store:{read:async()=>null,create:async()=>true},bundled:async()=>{bundled++;return font;}});
 const s=setup();let auth=0;s.deps.authorize=async()=>++auth===1?admission:false;s.deps.font=id=>resolver.resolve(id);
 const value={occasionId:7,mode:'font',fontProtocol:2,fontId:futuraId};
 assertEquals((await handlePreview(req(value),s.deps)).status,200);assertEquals((await handlePreview(req(value),s.deps)).status,403);assertEquals([auth,bundled],[2,1]);
});
Deno.test('font selection, draft canvas resources, preview and shared download/email renderer use identical pinned bytes',async()=>{
 const {TicketFontResolver,fontCatalog,futuraId,digest}=await import('../_shared/ticketFonts.ts');
 const {prepareTicketRenderer}=await import('../_shared/ticketGeneration.ts');
 const {PDFDocument,PDFDict,PDFName,PDFRawStream}=await import('npm:pdf-lib');
 const {inflateSync}=await import('node:zlib');
 const asset=fontCatalog.find(a=>a.family==='Roboto Slab')!;
 const bytes=await Deno.readFile('test/fixtures/ticket_fonts/Roboto-Slab.ttf');
 const resolver=new TicketFontResolver({fetch:async()=>{throw Error('network');},store:{read:async()=>null,create:async()=>true},bundled:async a=>a.id===futuraId?font:bytes});
 const selected=await resolver.resolve(asset.id),base=await resolver.resolve(futuraId);
 const resources={fonts:{[asset.id]:selected,[futuraId]:base},font,metrics};
 const t={...preset('named'),fontId:asset.id};const layout={schemaVersion:3 as const,templates:{named:t}};
 const occasion={id:7,features:[{code:'ticket',ticket_type:'named',layout}],data:{}};
 const s=setup();s.deps.font=id=>resolver.resolve(id);s.deps.occasion=async()=>occasion;s.deps.resources=async()=>resources;
 const selectedReply=await (await handlePreview(req({occasionId:7,mode:'font',fontProtocol:2,fontId:asset.id}),s.deps)).json();
 const resolved=await (await handlePreview(req({...body,layout,fontProtocol:2}),s.deps)).json();
 const decoded=(text:string)=>Uint8Array.from(atob(text),c=>c.charCodeAt(0));
 assertEquals(await digest(decoded(selectedReply.font)),asset.sha256);assertEquals(resolved.fonts[asset.id].font,selectedReply.font);assertEquals(resolved.fonts[asset.id].metrics,selected.metrics);
 const preview=await (await handlePreview(req({...body,mode:'pdf',layout,fontProtocol:2}),s.deps)).json();
 const renderer=await prepareTicketRenderer(occasion,{}, {},{load:async()=>resources,products:async()=>({product_types:[],products:[]})});
 const embeddedHashes=async(bytes:Uint8Array)=>{const doc=await PDFDocument.load(bytes);const descriptors=doc.context.enumerateIndirectObjects().map(([,o])=>o).filter(o=>o instanceof PDFDict&&o.has(PDFName.of('FontFile2'))) as PDFDictType[];return await Promise.all(descriptors.map(async d=>{const stream=doc.context.lookup(d.get(PDFName.of('FontFile2'))) as PDFRawStreamType;return await digest(inflateSync(stream.getContents()));}));};
 const ticket={ticket_symbol:'12341A2C3E'};
 for(const pdf of [decoded(preview.file),(await renderer(ticket)).bytes,(await renderer(ticket)).bytes])assertEquals(await embeddedHashes(pdf),[asset.sha256]);
});

Deno.test('catalog-only retry reads no resources; reference failure precedes resource access',async()=>{
 const s=setup();
 const response=await handlePreview(req({occasionId:7,mode:'catalog'}),s.deps);
 assertEquals(response.status,200);assertEquals(s.counts(),[1,0,1]);
 const {productTemplate,rawCatalog}=await import('../../../test/fixtures/ticket_layout/products.ts');
 const {indexProductCatalog}=await import('../_shared/ticketRenderData.ts');
 const t=productTemplate();t.elements.at(-1)!.productTypeId=999;
 const other=setup();other.deps.products=async()=>indexProductCatalog(rawCatalog,7);
 assertEquals((await handlePreview(req({...body,type:'wide',layout:{schemaVersion:3,templates:{wide:t}}}),other.deps)).status,400);
 assertEquals(other.counts()[1],0);
});
Deno.test('blank setup draft borrows resources without exposing source product fields or catalog',async()=>{
 const s=setup();const {productTemplate,rawCatalog}=await import('../../../test/fixtures/ticket_layout/products.ts');const {indexProductCatalog}=await import('../_shared/ticketRenderData.ts');
 s.deps.occasion=async()=>({id:7,features:[{code:'ticket',layout:{schemaVersion:3,templates:{wide:productTemplate()}}}]});
 s.deps.products=async()=>indexProductCatalog(rawCatalog,7);
 const result=await (await handlePreview(req({...body,type:'wide',borrowResourcesOnly:true}),s.deps)).json();
 assertEquals(result.catalog,[]);assertEquals(result.template.elements.some((e:any)=>e.binding==='productType'),false);
});

Deno.test('preview denies central output exhaustion without returning a partial PDF',async()=>{
 const s=setup();s.deps.authorize=async()=>({abuseLimits:{...admission.abuseLimits,'document.output.bytes':1}});
 assertEquals((await handlePreview(req(),s.deps)).status,429);
});

Deno.test('unconfigured preview uses the production default and retains legible event details',async()=>{
  const {resolveTicketTemplate}=await import('../_shared/ticketGeneration.ts');
  const s=setup();
  const occasion={id:7,title:'Podzimní slavnost',start_time:'2026-11-07T18:00:00Z',data:{place_name:'Kulturní dům'},features:[{code:'ticket',ticket_type:'wide',darkColor:'FFFFFF'}]};
  s.deps.occasion=async()=>occasion;
  const response=await handlePreview(req({...body,type:'wide'}),s.deps);
  assertEquals(response.status,200);
  const result=await response.json();
  assertEquals(result.template,await resolveTicketTemplate(occasion,{font,metrics}));
  assertEquals(result.data.occasionTitle,occasion.title);
  assert(result.data.occasionDatePlace.includes('Kulturní dům'));
  assertEquals(result.template.canvasColor,'FFFFFF');
  assertEquals(result.template.elements.find((e:any)=>e.binding==='occasionTitle').style.color,'165C55');
});

Deno.test('draft preview text overrides scenarios while resource authorization stays on the saved occasion',async()=>{
  const s=setup();
  const source={id:7,organization:3,title:'Borrowed source',start_time:'2025-01-01T18:00:00Z',data:{place_name:'Source hall'},features:[]};
  const previewOccasion={title:'Nový podzimní ples',start_time:'2026-11-07T18:00:00.000Z',end_time:'2026-11-07T22:00:00.000Z',data:{place_name:'Sokolovna v Brně'}};
  s.deps.authorize=async(_auth,id)=>{assertEquals(id,7);return admission;};
  s.deps.occasion=async(id)=>{assertEquals(id,7);return source;};
  s.deps.resources=async(occasion)=>{assertEquals(occasion,source);return {font,metrics};};
  const response=await handlePreview(req({...body,borrowResourcesOnly:true,previewOccasion}),s.deps);
  assertEquals(response.status,200);
  const result=await response.json();
  for(const data of [result.data,...Object.values(result.scenarios)] as any[]) {
    assertEquals(data.occasionTitle,previewOccasion.title);
    assert(data.occasionDatePlace.includes(previewOccasion.data.place_name));
    assert(!data.occasionDatePlace.includes('Source'));
    assertEquals(data.occasionStartTime,'19:00');
  }
  const pdf=await handlePreview(req({...body,mode:'pdf',previewOccasion}),s.deps);
  assertEquals(pdf.status,200);
  assert(atob((await pdf.json()).file).startsWith('%PDF'));
  const empty=await handlePreview(req({...body,previewOccasion:{title:'',start_time:null,end_time:null,data:{place_name:null}}}),s.deps);
  const emptyData=(await empty.json()).data;
  assertEquals(emptyData.occasionTitle,null);
  assertEquals(emptyData.occasionDatePlace,null);
});

Deno.test('draft preview rejects identity, asset, malformed and unbounded context before resource reads',async()=>{
  const invalid=[null,[],{title:'x',id:8},{title:'x',organization:3},{title:'x',features:[]},{title:'x',data:{logo:'https://img.festapp.net/logo.png'}},{title:'x',data:{link:'https://example.com'}},{title:'x',data:[]},{title:42},{title:'x'.repeat(501)},{title:'x',data:{place_name:'x'.repeat(501)}},{title:'x',start_time:'yesterday'},{title:'x',end_time:'2026-01-01'},{title:'x',start_time:42},{title:'x',start_time:'2026-13-99T18:00:00Z'}];
  for(const previewOccasion of invalid) {
    const s=setup();
    assertEquals((await handlePreview(req({...body,previewOccasion}),s.deps)).status,400);
    assertEquals(s.counts(),[0,0,0]);
  }
  for(const extra of [{readOnly:true},{mode:'catalog'},{mode:'font',fontId:futuraId}]) {
    const s=setup();
    assertEquals((await handlePreview(req({...body,...extra,previewOccasion:{title:'Draft'}}),s.deps)).status,400);
    assertEquals(s.counts(),[0,0,0]);
  }
});
