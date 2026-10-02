import {assert,assertEquals,assertRejects,assertThrows} from 'jsr:@std/assert@1';
import {fontBytes,fontMetrics,generateTicketPdf,prepareTicketRenderer,resolveTicketTemplate} from './ticketGeneration.ts';
import {importTicketTemplate} from './ticketTemplateImport.ts';
import {positionedElements,parseLayout,preset} from './ticketLayout.ts';
import {sampleData} from './ticketRenderData.ts';
import {PDFDocument} from 'npm:pdf-lib';
const font=await fontBytes('robotoSlab');
const resources={font,metrics:fontMetrics(font),background:await Deno.readFile('test/fixtures/ticket_layout/historical/forest.jpg')};
const occasion={id:27,features:[{code:'ticket',ticket_type:'wide',background:'https://img.festapp.net/forest.jpg',darkColor:'FFFFFF',lightColor:'000000'}]};
Deno.test('existing wide ticket imports its physical geometry, original font, inverted QR and compact rows',async()=>{
 const t=await importTicketTemplate(occasion,resources);
 assertEquals(t.font,'robotoSlab');assertEquals(t.qrAppearance,{background:'000000',opacity:192/255,margin:1.6});
 assertEquals(t.page,{width:595.28,height:841.89});
 const doc=await PDFDocument.create();const image=await doc.embedJpg(resources.background);const scale=535.752/image.width;
 const q=t.elements.find(e=>e.binding==='qr')!;assert(Math.abs(q.box.width-240*scale)<.001);
 assert(Math.abs(q.box.y-(t.ticketArea.height-380*scale))<.001);
 const d=sampleData();const positioned=positionedElements(t,d);const food=positioned.find(e=>e.binding==='food')!,price=positioned.find(e=>e.binding==='price')!;
 assertEquals(Math.round((price.box.y-food.box.y)/scale),50);
 const pdf=await generateTicketPdf(d,resources,t);assertEquals((await PDFDocument.load(pdf.bytes)).getPage(0).getSize(),t.page);
});
Deno.test('both named fonts import without losing original baseline or page geometry',async()=>{
 for(const name of ['roboto','russoOne']){
 const f=await fontBytes(name);const t=await importTicketTemplate({features:[{code:'ticket',ticket_type:'named'}],data:name==='russoOne'?{font:'https://fonts.cdnfonts.com/s/15876/RussoOne-Regular.woff'}:{}},{font:f,metrics:fontMetrics(f)});
 assertEquals(t.font,name);assertEquals(t.page,{width:212.5,height:387.5});parseLayout({schemaVersion:1,templates:{named:t}});
 const title=t.elements.find(e=>e.binding==='occasionTitle')!;assertEquals(title.box.y+title.style.fontSize*fontMetrics(f).ascent,87.5);
 }
});
Deno.test('saved edits win; preview and download use the same imported document and batch resources once',async()=>{
 const saved=preset('wide');const edited={...occasion,features:[{...occasion.features[0],layout:{schemaVersion:1,templates:{wide:saved}}}]};
 assertEquals(await resolveTicketTemplate(edited,resources),saved);
 let loads=0,products=0;
 const render=await prepareTicketRenderer(occasion,{}, {},{load:async()=>{loads++;return resources;},products:async()=>{products++;return {products:[],product_types:[]};}});
 const t={ticket_symbol:'X3829W6R7W',price:200};
 for(let i=0;i<2;i++)assert((await render(t)).bytes.length>1000);
 assertEquals([loads,products],[1,1]);
});
Deno.test('unsupported arbitrary historical fonts fail explicitly instead of silently substituting',async()=>{
 const {loadLayoutResources}=await import('./ticketGeneration.ts');
 await assertRejects(()=>loadLayoutResources({features:[{code:'ticket',ticket_type:'named'}],data:{font:'https://example.com/unknown.woff'}}));
});

Deno.test('appearance contract rejects unknown fonts and malformed QR or flow',()=>{
 const t=preset('wide');
 for(const appearance of [{font:'unknown'},{qrAppearance:null},{qrAppearance:{background:'FFFFFF',opacity:2,margin:4}},{flow:['qr']},{flowStep:0},{border:1}])assertThrows(()=>parseLayout({schemaVersion:1,templates:{wide:{...t,...appearance}}}));
});
