import {assertEquals,assertThrows} from 'jsr:@std/assert@1';
import {draftPreviewProducts} from './draftProducts.ts';
import {indexProductCatalog,sampleData} from '../_shared/ticketRenderData.ts';
import {ticketGallery} from '../_shared/ticketGallery.ts';

Deno.test('draft previews use configured ticket prices, zero, currency and stable local IDs',()=>{
 for(const price of [0,290,795]) {
  const draft={formDraft:{fields:[{product_type_data:{id:-101,type:'spot',title:'Vstupné',products:[
   {id:-201,title:'Skrytá stará cena',price:9999,is_hidden:true,currency_code:'CZK'},
   {id:-202,title:'Běžné vstupné',price,currency_code:'CZK'},
  ]}}]}};
  const catalog=draftPreviewProducts(draft);
  assertEquals(catalog.types.get(-101)?.example?.id,-202);
  assertEquals(catalog.types.get(-101)?.example?.price,price);
  assertEquals(catalog.types.get(-101)?.example?.currency_symbol,'Kč');
  for(const template of Object.values(ticketGallery())) {
   const data=sampleData('normal',undefined,catalog,template);
   assertEquals(data.price,`Cena: ${price}\u00a0Kč`);
  }
 }
});
Deno.test('hidden draft fields are never the displayed admission price; edits replace previous prices',()=>{
 const draft={formDraft:{fields:[{is_hidden:true,product_type_data:{id:-1,type:'spot',products:[{id:-10,title:'Old',price:9999}]}},
  {product_type_data:{id:-2,type:'spot',products:[{id:-20,title:'Vstupné',price:350}]}}]}};
 assertEquals(draftPreviewProducts(draft).types.get(-1)?.example,null);
 assertEquals(draftPreviewProducts(draft).types.get(-2)?.example?.price,350);
 draft.formDraft.fields[1].product_type_data.products[0].price=650;
 assertEquals(draftPreviewProducts(draft).types.get(-2)?.example?.price,650);
 assertEquals(draftPreviewProducts({formDraft:{fields:[]}}).types.size,0);
 assertThrows(()=>indexProductCatalog({product_types:[{id:-2,occasion:7}],products:[]},7));
});
