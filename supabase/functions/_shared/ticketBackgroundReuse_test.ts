import { assertEquals, assert } from 'jsr:@std/assert@1';
import { PDFDocument, PDFName, PDFRawStream, PDFDict } from 'npm:pdf-lib';
import { inflateSync } from 'node:zlib';
import { prepareTicketRenderer, generateTicketPdf } from './ticketGeneration.ts';
import { fontMetrics } from './ticketFonts.ts';
import { preset } from './ticketLayout.ts';
import { sampleData } from './ticketRenderData.ts';
const font=await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');
const metrics=fontMetrics(font);
const background=Uint8Array.from(atob('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=='),c=>c.charCodeAt(0));
const t=preset('wide');t.backgroundTransform={scale:1.4,x:-.1,y:.05};
const occasion={id:1,title:'Testovací ples',features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:1,templates:{wide:t}}}]};
async function images(bytes:Uint8Array){
 const doc=await PDFDocument.load(bytes);const result=[];
 for(const [,object] of doc.context.enumerateIndirectObjects())if(object instanceof PDFRawStream&&object.dict.get(PDFName.of('Subtype'))===PDFName.of('Image')){
  const decoded=object.dict.get(PDFName.of('Filter'))===PDFName.of('FlateDecode')?inflateSync(object.getContents()):object.getContents();
  result.push({width:String(object.dict.get(PDFName.of('Width'))),height:String(object.dict.get(PDFName.of('Height'))),pixels:Array.from(decoded)});
 }
 return result.sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
}
Deno.test('eight independent ticket PDFs decode the batch background once and preserve image transparency',async()=>{
 const original=PDFDocument.prototype.embedPng;let embeds=0;
 PDFDocument.prototype.embedPng=function(input){embeds++;return original.call(this,input);};
 try{
  const resources={font,metrics,background};
  const render=await prepareTicketRenderer(occasion,{}, {}, {load:async()=>resources,products:async()=>({products:[],product_types:[]})});
  const symbols=Array.from({length:8},(_,i)=>`FAKE${String(i).padStart(6,'0')}`);
  const results=await Promise.all(symbols.map(ticket_symbol=>render({ticket_symbol,price:450,currency_code:'CZK'})));
  assertEquals(embeds,1);
  assertEquals('preparedBackground' in resources,false,'caller-owned resources must remain unchanged');
  const baseline=await generateTicketPdf(sampleData(),resources,t);
  for(const result of results){
   const doc=await PDFDocument.load(result.bytes);
   assertEquals(doc.getPageCount(),1);assertEquals(doc.getPage(0).getSize(),{width:t.page.width,height:t.page.height});
   assertEquals(await images(result.bytes),await images(baseline.bytes));
   assert(result.bytes.length>1000);
  }
  assertEquals(new Set(results.map(r=>Array.from(r.bytes).join(','))).size,8);
  await prepareTicketRenderer(occasion,{}, {}, {load:async()=>({...resources,background:background.slice()}),products:async()=>({})});
  assertEquals(embeds,3,'a separate batch owns a separate prepared image');
 }finally{PDFDocument.prototype.embedPng=original;}
});
Deno.test('a batch without artwork retains the existing renderer path',async()=>{
 const render=await prepareTicketRenderer(occasion,{}, {}, {load:async()=>({font,metrics}),products:async()=>({})});
 const result=await render({ticket_symbol:'FAKE000009',price:450,currency_code:'CZK'});
 assertEquals(await images(result.bytes),[]);
});
Deno.test('JPEG artwork retains its exact encoded image in each independent PDF',async()=>{
 const jpg=await Deno.readFile('test/fixtures/ticket_layout/historical/cream.jpg');
 const resources={font,metrics,background:jpg};
 const render=await prepareTicketRenderer(occasion,{}, {}, {load:async()=>resources,products:async()=>({})});
 const baseline=await generateTicketPdf(sampleData(),resources,t);
 for(let i=0;i<2;i++)assertEquals(await images((await render({ticket_symbol:`FAKE00001${i}`})).bytes),await images(baseline.bytes));
});
