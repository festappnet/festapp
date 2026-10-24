import {normalizeTicketData} from './ticketRenderData.ts';
import {assertEquals,assertRejects,assert} from 'jsr:@std/assert@1';
import {batchPrintPartSize,sealBatchResources,renderBatchPart,readBatchStoredPdf,type BatchObjectStore} from './ticketBatchDocuments.ts';
import {fontCatalog,fontMetrics,digest} from './ticketFonts.ts';
import {preset} from './ticketLayout.ts';
import {PDFDocument} from 'npm:pdf-lib';
const fontAsset=fontCatalog.find(f=>f.family==='Roboto')!;
const fontBytes=await Deno.readFile('test/fixtures/ticket_fonts/Roboto.ttf');
const font={id:fontAsset.id,bytes:fontBytes,metrics:fontMetrics(fontBytes),family:'Roboto',weight:400};
const abuseLimits={'document.input.bytes':4194304,'document.asset.bytes':16777216,'document.output.bytes':16777216,'document.output.pages':20};
function setup() {
 const data=new Map<string,Uint8Array>();
 const store:BatchObjectStore={read:async key=>data.get(key)?.slice()??null,create:async(key,bytes)=>{if(!data.has(key))data.set(key,bytes.slice());}};
 const template=preset('wide');template.fontId=font.id;
 const claim={batchId:'ba000000-0000-0000-0000-000000000001',abuseLimits,snapshot:{renderContractVersion:1,
 occasion:{id:7,title:'Frozen title',features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:3,templates:{wide:template}}}]},
 catalog:{products:[],product_types:[]},documentData:[{ticket:{id:1,occasion:7,state:'ordered',ticket_symbol:'12341A2C3E',order_product_ticket:[]}}]}};
 const load=async()=>({fonts:{[font.id]:font},font:font.bytes,metrics:font.metrics});
 return {store,data,claim,load};
}
Deno.test('sealed batch renderer uses private bytes and preserves completed download after sale/catalog changes',async()=>{
 const s=setup();const manifest=await sealBatchResources(s.claim,s.store,s.load);
 const claim={...s.claim,manifest,ticketIds:[1]};
 const rendered=await renderBatchPart(claim,s.store);
 assertEquals((await PDFDocument.load(rendered.bytes)).getPageCount(),1);
 const key=`${s.claim.batchId}/manifest/single-001.pdf`;
 await s.store.create(key,rendered.bytes,'application/pdf');
 const doc={objectKey:key,digest:rendered.digest,bytes:rendered.bytes.length};
 s.claim.snapshot.occasion.title='New live title';
 // Completed reads return the exact stored bytes, regardless of current order/catalog.
 assertEquals(await digest(await readBatchStoredPdf(doc,s.store)),rendered.digest);
 assertEquals(await readBatchStoredPdf(doc,s.store),rendered.bytes);
});
Deno.test('batch output, corrupt resources, forged keys and failed uploads are rejected',async()=>{
 const s=setup();const manifest=await sealBatchResources(s.claim,s.store,s.load);
 await assertRejects(()=>renderBatchPart({...s.claim,manifest,ticketIds:Array(21).fill(1)},s.store));
 const asset=manifest.resources.fonts[font.id];
 s.data.set(asset.key,new Uint8Array([0,1,2]));
 await assertRejects(()=>renderBatchPart({...s.claim,manifest,ticketIds:[1]},s.store));
 const t=setup();const frozen=await sealBatchResources(t.claim,t.store,t.load);
 frozen.resources.fonts[font.id].key='other/resources/font';
 await assertRejects(()=>renderBatchPart({...t.claim,manifest:frozen,ticketIds:[1]},t.store));
 await assertRejects(()=>sealBatchResources(t.claim,{read:async()=>null,create:async()=>{}},t.load));
 assert(t.data.size>0);
});

Deno.test('frozen batch price preserves minor units without changing ordinary ticket formatting',()=>{
 const ticket={ticket_symbol:'fixture',price:100.25,currency_code:'CZK',order_product_ticket:[]};
 const ordinary=normalizeTicketData(ticket,{id:7});
 const frozen=normalizeTicketData({...ticket,price_decimal_digits:2},{id:7});
 assert(frozen.price!.includes('100,25'));
 assert(!ordinary.price!.includes('100,25'));
});

Deno.test('large frozen resources choose smaller fixed print parts within the existing page policy',()=>{
 assertEquals(batchPrintPartSize(50000,20,16777216),20);
 assert(batchPrintPartSize(4*1024*1024,20,16777216)<20);
 assertEquals(batchPrintPartSize(16*1024*1024,20,16777216),1);
 assertEquals(batchPrintPartSize(50000,2,16777216),2);
});
