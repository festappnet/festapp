import {fontMetrics} from './ticketFonts.ts';
import {assertEquals,assertThrows,assert,assertRejects} from 'jsr:@std/assert@1';
import {parseLayout,preset,pdfBox} from './ticketLayout.ts';
import {fitText} from './ticketText.ts';
import {normalizeTicketData,sampleData,sampleSymbol,sampleQr} from './ticketRenderData.ts';
import {generateTicketPdf,activeTemplate,prepareTicketRenderer} from './ticketGeneration.ts';
import {PDFDocument,PDFRawStream,PDFName} from 'npm:pdf-lib';
import {inflateSync} from 'node:zlib';
const font=await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');const metrics=fontMetrics(font);
const png=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),c=>c.charCodeAt(0));
const r={font,metrics,background:png,logo:png};
Deno.test('both presets round trip and stay printable at extreme aspect ratios',()=>{
  for(const type of ['wide','named'] as const)for(const [w,h] of [[1600,800],[3200,80],[20,3000]]) {
    const t=preset(type,w,h);assertEquals(t.elements.find(e=>e.binding==='ticketSymbol')!.style.align,'center');const layout={schemaVersion:1,templates:{[type]:t}};
    assertEquals(parseLayout(layout),layout);
    const q=t.elements.find(e=>e.binding==='qr')!;const b=pdfBox(t,q.box);
    assertEquals(b.y,t.page.height-t.ticketArea.y-q.box.y-q.box.height);
  }
});
Deno.test('layout rejects missing, duplicate, hidden, distorted and overlapping QR and unknown versions',()=>{
  const base={schemaVersion:1,templates:{named:preset('named')}};
  const invalid=[(v:any)=>v.schemaVersion=3,(v:any)=>v.templates.named.elements.push(v.templates.named.elements[0]),(v:any)=>v.templates.named.elements=v.templates.named.elements.filter((e:any)=>e.binding!=='qr'),(v:any)=>v.templates.named.elements.find((e:any)=>e.binding==='qr').visible=false,(v:any)=>v.templates.named.elements.find((e:any)=>e.binding==='qr').box.width=30,(v:any)=>v.templates.named.elements[1].box=v.templates.named.elements.find((e:any)=>e.binding==='qr').box,(v:any)=>v.templates.named.elements[0].box.x=-1,(v:any)=>v.templates.named.elements[0].style.fontSize=Infinity,(v:any)=>v.templates={}];
  for(const mutate of invalid){const v=structuredClone(base);mutate(v);assertThrows(()=>parseLayout(v));}
  assertEquals(activeTemplate({features:[{code:'ticket',ticket_type:'wide'}]}),undefined);
  assertThrows(()=>activeTemplate({features:[{code:'ticket',layout:{schemaVersion:2}}]}));
});
Deno.test('normalization preserves zero, deterministic first product, public note and order name',()=>{
  const d=normalizeTicketData({ticket_symbol:'12341A2C3E',price:0,note_hidden:'NEVER PRINT',order_product_ticket:[{id:8,product:2},{id:1,product:1}]},{data:{}},{name:' Jana ',surname:' Nováková '},{food:{1:{title:'První'},2:{title:'Druhá'}}});
  assertEquals(d.food,'Večeře: První');assertEquals(d.orderName,'Jana Nováková');assert(d.price?.includes('0'));assertEquals(d.note,null);
  assert(/^[1-9X]{4}[1-9][ACEFGHIJKLMNPQRUVWXY][1-9][ACEFGHIJKLMNPQRUVWXY][1-9][ACEFGHIJKLMNPQRUVWXY]$/.test(sampleSymbol));
});
Deno.test('preview uses realistic purchased values without a live admission QR',()=>{
  const d=sampleData();
  assertEquals(d.ticketSymbol,sampleSymbol);
  assertEquals(d.qr,sampleQr);
  assertEquals(d.spotGroup,'Stůl: 12');
  assertEquals(d.food,'Večeře: Steak z panenky + štouch. brambory');
  assert(d.price?.includes('370'));
  assertEquals(d.note,null);
  assert(!/^[1-9X]{4}[1-9][ACEFGHIJKLMNPQRUVWXY][1-9][ACEFGHIJKLMNPQRUVWXY][1-9][ACEFGHIJKLMNPQRUVWXY]$/.test(d.qr!));
  assert(!JSON.stringify(d).includes('VZOR'));
  const current=sampleData('normal',{id:81,organization:3});
  assertEquals(current.ticketSymbol,'X3817K6M8R');
  assertEquals(current.qr,'festapp-preview:X3817K6M8R');
});
Deno.test('text wraps long words, shrinks, warns and never truncates ticket symbol',()=>{
  const e=preset('wide').elements.find(e=>e.binding==='note')!;
  const fit=fitText('PřílišDlouhéSlovoBezMezer'.repeat(80),e,metrics);assert(fit.overflow);assert(fit.lines.at(-1)?.endsWith('…'));assert(fit.widths.every(w=>w<=e.box.width));
  assertThrows(()=>fitText('12341A2C3E',{...e,binding:'ticketSymbol',box:{...e.box,width:1}},metrics));
});
Deno.test('custom PDFs contain one vector QR with four quiet modules and fixed physical pages',async()=>{
  for(const type of ['wide','named'] as const){
    const t=preset(type);const output=await generateTicketPdf(sampleData(),r,t,type,true);const doc=await PDFDocument.load(output.bytes);
    assertEquals(doc.getPage(0).getSize(),t.page);
    const streams=doc.context.enumerateIndirectObjects().filter(([,o])=>o instanceof PDFRawStream).map(([,o])=>o as PDFRawStream);
    const ops=streams.filter(s=>s.dict.get(PDFName.of('Filter'))?.toString()==='/FlateDecode').map(s=>new TextDecoder().decode(inflateSync(s.getContents()))).filter(s=>s.includes('0 0 m\n'));
    assert(ops.length>0);assert((ops.join('').match(/0 0 m\n/g)||[]).length>100,'QR must be vector modules');
  }
});
Deno.test('render rejects invalid custom template before producing bytes',async()=>{
  const t=preset('named');t.elements.find(e=>e.binding==='qr')!.visible=false;
  await assertRejects(()=>generateTicketPdf(sampleData(),r,t,'named'));
});

Deno.test('shared SQL fixtures are identical to the Dart/TS fixtures',async()=>{
  const fixtures=JSON.parse(await Deno.readTextFile(new URL('../../../test/fixtures/ticket_layout/layouts.json',import.meta.url)));
  for(const layout of fixtures.valid)parseLayout(layout);
  for(const layout of Object.values(fixtures.invalid))assertThrows(()=>parseLayout(layout));
  const sql=await Deno.readTextFile(new URL('../../../database/tests/ticket_layout_settings_test.sql',import.meta.url));
  assertEquals(JSON.parse(sql.split('$fixtures$')[1]),fixtures);
});
Deno.test('gallery keeps ordinary tickets on A4 and named tickets ticket-sized in either slot',async()=>{
  const {ticketPresets}=await import('./ticketLayout.ts');
  for(const type of ['wide','named'] as const){
    const styles=ticketPresets();
    assertEquals(Object.keys(styles).length,6);
    for(const [key,t] of Object.entries(styles)) {if(key.startsWith('portrait')) {assertEquals(t.pageFit,'ticket');assertEquals(t.page,{width:t.ticketArea.width,height:t.ticketArea.height});} else {assertEquals(t.pageFit,undefined);assertEquals(t.page,{width:595.28,height:841.89});}}
    for(const t of Object.values(styles))parseLayout({schemaVersion:1,templates:{[type]:t}});
    assert(JSON.stringify(styles.compact)!==JSON.stringify(styles.event));
  }
});
Deno.test('every named and bitmap style renders through the existing generators',async()=>{
  const {ticketPresets}=await import('./ticketLayout.ts');
  const {loadLayoutResources}=await import('./ticketGeneration.ts');
  const background=await loadLayoutResources({features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:1,templates:{wide:preset('wide')}}}],data:{}});
  assertEquals(background.background,undefined);
  for(const type of ['named','wide'] as const)for(const template of Object.values(ticketPresets())){
    const result=await generateTicketPdf(sampleData('long'),background,template,type,true);
    const doc=await PDFDocument.load(result.bytes);assertEquals(doc.getPageCount(),1);
  }
});

Deno.test('emphasis is optional, strictly boolean and rendered into actual PDF text operations',async()=>{
  const t=preset('named');
  const title=t.elements.find(e=>e.binding==='occasionTitle')!;
  for(const key of ['bold','italic','underline']) {
    const invalid=structuredClone(t); (invalid.elements.find(e=>e.binding==='occasionTitle')!.style as any)[key]='true';
    assertThrows(()=>parseLayout({schemaVersion:1,templates:{named:invalid}}));
  }
  Object.assign(title.style,{bold:true,italic:true,underline:true});
  const layout={schemaVersion:1 as const,templates:{named:t}};
  assertEquals(parseLayout(layout),layout);
  const output=await generateTicketPdf(sampleData('normal'),r,t);
  const doc=await PDFDocument.load(output.bytes);
  const streams=doc.context.enumerateIndirectObjects().filter(([,o])=>o instanceof PDFRawStream).map(([,o])=>o as PDFRawStream);
  const ops=streams.filter(s=>s.dict.get(PDFName.of('Filter'))?.toString()==='/FlateDecode').map(s=>new TextDecoder().decode(inflateSync(s.getContents()))).join('\n');
  assert(ops.includes('2 Tr'),'bold must use fill and outline in the PDF');
  assert(ops.includes('0.212556'),'italic must shear the actual PDF glyphs');
  assert(ops.includes(' l\nS'),'underline must draw a stroked line');
});

Deno.test('styled text fitting agrees with the shared editor fixtures',async()=>{
 const cases=JSON.parse(await Deno.readTextFile('test/fixtures/ticket_layout/text-emphasis.json'));
 const fixture=JSON.parse(await Deno.readTextFile('test/fixtures/ticket_layout/resolve.json'));
 for(const item of cases)assertEquals(fitText(item.text,item.element,fixture.metrics),item.expected);
});

Deno.test('custom QR colors validate and render beyond the suggested palette',async()=>{
 const {qrColorReadable}=await import('./ticketLayout.ts');
 for(const color of ['445566','5A245A','003F88','767676'])assert(qrColorReadable(color));
 for(const color of ['777777','FFFFFF','FFFF00','oops'])assert(!qrColorReadable(color));
 const t=preset('named');t.elements.find(e=>e.binding==='qr')!.style.color='445566';
 const output=await generateTicketPdf(sampleData('normal'),r,t);
 assert(output.bytes.length>1000);
});

Deno.test('landscape gallery contains only variable ticket data; named templates retain event and person details',async()=>{
 const {ticketPresets}=await import('./ticketLayout.ts');
 for(const [key,t] of Object.entries(ticketPresets())) {
   const bindings=t.elements.map(e=>e.binding);
   if(key.startsWith('portrait')) {
     for(const binding of ['occasionTitle','occasionDatePlace','orderName'])assert(bindings.includes(binding as any));
   } else {
     assertEquals([...bindings].sort(),['qr','ticketSymbol','spotGroup','food','note','price'].sort());
     const result=await generateTicketPdf(sampleData('normal'),r,t);
     assert(result.bytes.length>1000);
   }
 }
});