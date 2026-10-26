import {assertEquals,assertThrows} from 'jsr:@std/assert@1';
import {indexProductCatalog,normalizeTicketData,sampleData,formatProduct} from './ticketRenderData.ts';
import {preset,validateLayout,type Template} from './ticketLayout.ts';
import {rawCatalog,productTemplate} from '../../../test/fixtures/ticket_layout/products.ts';
Deno.test('ticket rendering preserves product and seat selection across SQL result permutations',()=>{
 const catalog=indexProductCatalog(rawCatalog,7),template=productTemplate();
 const opts=[
  {id:8,product:1,spot_group_title:'Later group',spot_title:'8'},
  {id:1,product:2,spot_group_title:'First group',spot_title:'1'},
  {id:2,product:3},
 ];
 const ticket={occasion:7,ticket_symbol:'test-order-independent',state:'paid',price:123,currency_code:'CZK',note:'Public note',order_product_ticket:opts};
 const expected=normalizeTicketData(ticket,{id:7},{},catalog,template);
 assertEquals(expected.spotGroup,'Stůl: First group');
 assertEquals(expected.vip,'VIP menu: Skrytá historická večeře');
 for(const indexes of [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]) {
  const reordered={...ticket,order_product_ticket:indexes.map(i=>opts[i])};
  assertEquals(normalizeTicketData(reordered,{id:7},{},catalog,template),expected);
  assertEquals(reordered.order_product_ticket,indexes.map(i=>opts[i]),'renderer must not mutate SQL input');
 }
});
Deno.test('ID contract preserves deterministic historical selection and hides private notes',()=>{
 const catalog=indexProductCatalog(rawCatalog,7),t=productTemplate();
 validateLayout({schemaVersion:3,templates:{wide:t}});
 const ticket={ticket_symbol:'test',price:0,note_hidden:'SECRET',order_product_ticket:[{id:8,product:1},{id:1,product:2},{id:2,product:3}]};
 const data=normalizeTicketData(ticket,{id:7},{},catalog,t);
 assertEquals(data.vip,'VIP menu: Skrytá historická večeře');assertEquals(data.transport,'Autobus');assertEquals(data.note,null);
 assertEquals(normalizeTicketData({...ticket,order_product_ticket:[]},{id:7},{},catalog,t).vip,null);
 assertEquals(sampleData('normal',{id:7},catalog,t).vip,'VIP menu: Řízek');
 assertEquals(sampleData('missing',{id:7},catalog,t).vip,null);
 assertEquals(formatProduct('',null),null);
 assertEquals(normalizeTicketData({state:'storno',order_product_ticket:[{id:1,product:null}]},{id:7},{},catalog,t).vip,null);
 assertThrows(()=>normalizeTicketData({order_product_ticket:[{id:1,product:999}]},{id:7},{},catalog,t));
 assertThrows(()=>indexProductCatalog({...rawCatalog,product_types:[{id:123,occasion:8}]},7));
});
Deno.test('legacy metadata, duplicate IDs and invalid flow are rejected',()=>{
 const original={schemaVersion:3,templates:{wide:productTemplate()}};
 const mutations=[(v:any)=>v.schemaVersion=2,(v:any)=>v.schemaVersion=1,(v:any)=>v.templates.wide.elements.at(-1).productTypeId=123,(v:any)=>v.templates.wide.elements.at(-1).productTypeId=1.5,(v:any)=>v.templates.wide.elements.at(-1).productTypeId=9007199254740992,(v:any)=>v.templates.wide.elements.at(-1).binding='food',(v:any)=>v.templates.wide.elements.at(-1).legacyTypes=['food'],(v:any)=>v.templates.wide.flow=['qr'],(v:any)=>v.templates.wide.flow=['missing'],(v:any)=>v.templates.wide.flow=['vip','vip']];
 for(const mutate of mutations){const v=structuredClone(original);mutate(v);assertThrows(()=>validateLayout(v));}
});
Deno.test('shared formatter fixture and production batch remain canonical',async()=>{
 const fixtures=JSON.parse(await Deno.readTextFile('test/fixtures/ticket_layout/product-format.json'));
 for(const item of fixtures)assertEquals(formatProduct(item.label,item.value),item.expected);
 const {prepareTicketRenderer}=await import('./ticketGeneration.ts');const {fontMetrics,futuraId}=await import('./ticketFonts.ts');
 const font=await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf'),metrics=fontMetrics(font);
 let loads=0,products=0;
 const t=productTemplate();
 const render=await prepareTicketRenderer({id:7,features:[{code:'ticket',layout:{schemaVersion:3,templates:{wide:t}}}]},{},{},{load:async()=>{loads++;return {font,metrics,fonts:{[futuraId]:{id:futuraId,bytes:font,metrics,family:'Futura PT',weight:400}}};},products:async()=>{products++;return rawCatalog;}});
 for(let i=0;i<2;i++)assertEquals((await render({ticket_symbol:'X3827K6M8R',price:0,order_product_ticket:[{id:1,product:2},{id:2,product:3}]})).bytes.length>1000,true);
 assertEquals([loads,products],[1,1]);
});
Deno.test('preview never sums different currencies or turns unknown prices into zero',()=>{
 const mixed=structuredClone(rawCatalog);mixed.products.find(p=>p.id===3)!.currency_code='EUR';
 assertEquals(sampleData('normal',{id:7},indexProductCatalog(mixed,7),productTemplate()).price,null);
 const unknown=structuredClone(rawCatalog);unknown.products.find(p=>p.id===1)!.price=NaN;
 const data=sampleData('normal',{id:7},indexProductCatalog(unknown,7),productTemplate());
 assertEquals(data.vip,'VIP menu: Řízek');assertEquals(data.price,null);
});
Deno.test('currency symbols and prices match the shared canvas contract fixture',async()=>{
 const fixtures=JSON.parse(await Deno.readTextFile('test/fixtures/ticket_layout/product-price-format.json'));
 for(const item of fixtures){
  const raw=structuredClone(rawCatalog);for(const p of raw.products)p.currency_code=item.currency;
  raw.products.find(p=>p.id===1)!.price=item.amount;raw.products.find(p=>p.id===3)!.price=0;
  const catalog=indexProductCatalog(raw,7);
  assertEquals(catalog.types.get(123)?.example?.currency_symbol,item.symbol);
  assertEquals(sampleData('normal',{id:7},catalog,productTemplate()).price,item.expected);
 }
});

Deno.test('catalog examples prefer visible positive prices with stable order and id fallback',()=>{
 const products=[
  {id:1,product_type:1,title:'Bez večeře',price:0,order:0},
  {id:2,product_type:1,title:'Hidden paid',price:100,is_hidden:true,order:0},
  {id:6,product_type:1,title:'Later paid',price:200,order:2},
  {id:5,product_type:1,title:'Higher id',price:300,order:1},
  {id:4,product_type:1,title:'Večeře',price:100,order:1},
  {id:3,product_type:1,title:'Infinite',price:Infinity,order:0},
  {id:10,product_type:2,title:'Free later',price:0,order:2},
  {id:9,product_type:2,title:'Free first',price:0,order:1},
  {id:8,product_type:2,title:'Unknown later',price:NaN,order:2},
  {id:11,product_type:3,title:'Unknown',price:NaN,order:0},
  {id:12,product_type:3,title:'Negative',price:-1,order:1},
  {id:13,product_type:4,title:'Hidden only',price:10,is_hidden:true},
  {id:14,product_type:1,title:' ',price:10,order:-1},
 ].map(p=>({...p,currency_code:'CZK'}));
 const raw={product_types:[1,2,3,4].map(id=>({id,occasion:7,title:String(id)})),products};
 for(const ordered of [products,[...products].reverse()]) {
  const catalog=indexProductCatalog({...raw,products:ordered},7);
  assertEquals([...catalog.types.values()].map(t=>t.example?.id??null),[4,9,11,null]);
  assertEquals(catalog.types.get(3)?.example?.price,null);
 }
});

Deno.test('optional event fields use event timezone in preview and PDF data',()=>{
 const occasion={id:7,title:'Koncert',start_time:'2026-10-16T18:30:00Z',data:{timezone:'Europe/Prague',place_name:'Kulturní dům'}};
 const t=preset('named');
 for(const binding of ['occasionStartTime','occasionPlace'] as const)t.elements.push({...structuredClone(t.elements.find(e=>e.binding==='occasionDatePlace')!),id:binding,binding});
 validateLayout({schemaVersion:3,templates:{named:t}});
 const actual=normalizeTicketData({ticket_symbol:'test'},occasion,{},undefined,t);
 const preview=sampleData('normal',occasion,undefined,t);
 assertEquals(actual.occasionStartTime,'20:30');
 assertEquals(actual.occasionPlace,'Kulturní dům');
 assertEquals(preview.occasionStartTime,actual.occasionStartTime);
 assertEquals(preview.occasionPlace,actual.occasionPlace);
 assertEquals(normalizeTicketData({},{}).occasionStartTime,null);
 assertEquals(normalizeTicketData({},{start_time:'invalid'}).occasionStartTime,null);
 assertEquals(normalizeTicketData({},{}).occasionPlace,null);
 assertEquals(normalizeTicketData({},{...occasion,data:{timezone:'America/New_York'}}).occasionStartTime,'14:30');
 assertEquals(normalizeTicketData({},{...occasion,data:{timezone:'invalid'}}).occasionStartTime,'20:30');
});
Deno.test('repeatable free text validates and projects unchanged into preview and real tickets',()=>{
 const t=preset('wide');
 const body=t.elements.find(e=>e.binding==='note')!;
 t.elements.push({...body,id:'custom-a',binding:'text',text:'Vlastní text 🎟️'},
   {...body,id:'custom-b',binding:'text',text:'Další řádek\nText'});
 const layout={schemaVersion:3,templates:{wide:t}};
 validateLayout(layout);
 for(const data of [sampleData('normal',{id:7},undefined,t),normalizeTicketData({ticket_symbol:'X',order_product_ticket:[]},{id:7},{},undefined,t)]) {
  assertEquals(data['custom-a'],'Vlastní text 🎟️');
  assertEquals(data['custom-b'],'Další řádek\nText');
 }
 for(const mutate of [(v:any)=>delete v.templates.wide.elements.at(-1).text,
   (v:any)=>v.templates.wide.elements.at(-1).text=123,
   (v:any)=>v.templates.wide.elements.at(-1).text='a'.repeat(2001),
   (v:any)=>v.templates.wide.elements[0].text='unexpected']) {
  const invalid=structuredClone(layout);mutate(invalid);assertThrows(()=>validateLayout(invalid));
 }
});

Deno.test('English ticket retains admission QR, exact amount and event civil time', () => {
 const d=normalizeTicketData({ticket_symbol:'ADMISSION-123',note:'Vegetarian',price:12.34,currency_code:'EUR',order_product_ticket:[{id:1,spot_group_title:'A'}]},
 {id:7,locale:'en',title:'Starlight Ball',start_time:'2026-10-31T23:30:00Z',end_time:'2026-11-01T01:00:00Z',data:{timezone:'Europe/Prague'}},
 {name:'Alex',surname:'Morgan'});
 assertEquals(d.qr,'ADMISSION-123');
 assertEquals(d.spotGroup,'Table: A');
 assertEquals(d.note,'Note: Vegetarian');
 assertEquals(d.price,'Price: €12.34');
 assertEquals(d.occasionStartTime,'00:30');
 assertEquals(d.footer,'This ticket is non-transferable');
});

Deno.test('English date range keeps month before both days', () => {
  const data = normalizeTicketData({ticket_symbol:'ENRANGE123',price:350,currency_code:'CZK'},
    {locale:'en',title:'Evening',start_time:'2026-11-22T18:00:00Z',end_time:'2026-11-25T18:00:00Z',data:{timezone:'Europe/Prague'}});
  if (!/^Nov 22.*25, 2026$/.test(data.occasionDatePlace ?? '')) throw new Error(JSON.stringify(data));
});
