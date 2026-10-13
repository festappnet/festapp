// Offline-only migration regressions; the importer is not in the Edge graph.
import {assertEquals,assertRejects,assert} from 'jsr:@std/assert@1';
import {convert,candidates} from '../../../automation/tickets/product-type-cutover/convert.ts';
import {preset as legacyPreset} from '../../../automation/tickets/product-type-cutover/legacy-layout.ts';
import {fontMetrics} from './ticketFonts.ts';
import {resolveTicketTemplate} from './ticketGeneration.ts';
const font=await Deno.readFile('supabase/functions/_shared/ticket-assets/font.ttf');
const resources={font,metrics:fontMetrics(font)};
const row=(types:any[])=>({id:7,features:[{code:'ticket',ticket_type:'wide',layout:{schemaVersion:1,templates:{wide:legacyPreset('wide'),named:legacyPreset('named')}}}],product_types:types});
Deno.test('migration uses form reference and historical usage, not unused catalog candidates',async()=>{
 const input=row([{id:123,type:'food',form_references:1,ordered_count:0},{id:999,type:'food',form_references:0,ordered_count:0},{id:124,type:'taxi',form_references:1,ordered_count:3}]);
 assertEquals(candidates(input),[123]);
 const result=await convert(input);assertEquals(result.schemaVersion,3);
 const old=input.features[0].layout.templates.wide.elements.find(e=>e.binding==='food')!;
 const field=result.templates.wide.elements.find((e:any)=>e.binding==='productType');assertEquals(field.box,old.box);assertEquals(field.id,old.id);assertEquals(field.productTypeId,123);assertEquals(field.label,'Večeře');
 assertEquals(result.templates.wide.elements.filter((e:any)=>e.binding==='productType').length,1);
 const hidden=await convert(row([{id:123,type:'food',form_references:0,ordered_count:10}]));assertEquals(hidden.templates.wide.elements.find((e:any)=>e.binding==='productType').productTypeId,123);
 await assertRejects(()=>convert(row([{id:123,type:'food',form_references:1},{id:124,type:'food',ordered_count:1}])));
});
Deno.test('unused field is removed and runtime cannot implicitly import artwork',async()=>{
 const input=row([]),old=input.features[0].layout.templates.wide.elements;
 const result=await convert(input);
 assert(!result.templates.wide.elements.some((e:any)=>e.binding==='productType'));
 for(const e of result.templates.wide.elements)assertEquals(e.box,old.find(o=>o.id===e.id)!.box);
 await assertRejects(()=>resolveTicketTemplate({features:[{code:'ticket',background:'https://img.festapp.net/legacy.jpg'}]},resources));
});
Deno.test('named-only historical tickets do not invent ambiguous food fields in an absent slot',async()=>{
 const input={id:7,features:[{code:'ticket',ticket_type:'named'}],product_types:[{id:123,type:'food',form_references:1},{id:124,type:'food',form_references:1}]};
 const result=await convert(input,async()=>resources);
 for(const template of Object.values(result.templates) as import('./ticketLayout.ts').Template[])assert(!template.elements.some(e=>e.binding==='productType'));
});
Deno.test('implicit bitmap conversion preserves compact geometry and pinned historical font',async()=>{
 const {importTicketTemplate}=await import('../../../automation/tickets/product-type-cutover/legacy-import.ts');
 const {positionedElements}=await import('../../../automation/tickets/product-type-cutover/legacy-layout.ts');
 const {legacyFontIds}=await import('./ticketFonts.ts');
 const bitmap=await Deno.readFile('test/fixtures/ticket_layout/historical/forest.jpg');
 const oldFont=await Deno.readFile('supabase/functions/_shared/ticket-assets/roboto-slab.ttf');
 const r={font:oldFont,metrics:fontMetrics(oldFont),background:bitmap};
 const source={id:7,features:[{code:'ticket',ticket_type:'wide',background:'https://img.festapp.net/fixture.jpg'}],product_types:[]};
 const old=await importTicketTemplate(source,r);
 const converted=await convert(source,async()=>r);
 const expected=positionedElements(old,{spotGroup:'present',food:null,note:'present',price:'present'}).filter(e=>e.binding!=='food');
 assertEquals(converted.templates.wide.elements.map((e:any)=>e.box),expected.map(e=>e.box));
 assertEquals(converted.templates.wide.fontId,legacyFontIds.robotoSlab);
 assertEquals(converted.templates.wide.qrAppearance,old.qrAppearance);
 const {positionedElements:positionCanonical}=await import('./ticketLayout.ts');
 for(const data of [{spotGroup:'present',food:null,note:'present',price:'present'},{spotGroup:'present',food:null,note:null,price:'present'},{spotGroup:null,food:null,note:null,price:'present'}]) {
   const before=positionedElements(old,data).filter(e=>e.binding!=='food');
   const after=positionCanonical(converted.templates.wide,data);
   assertEquals(after.length,before.length);
   for(let i=0;i<after.length;i++) {
     for(const key of ['x','y','width','height'] as const) {
       assert(Math.abs(after[i].box[key]-before[i].box[key])<1e-9,`geometry changed: ${i}.${key}`);
     }
   }
 }

});
