import { assertEquals, assertStringIncludes, assertThrows } from "jsr:@std/assert@1";
import { generateChangeOverview, type OrderChangeSummary } from "./changeOverview.ts";
const fixture = JSON.parse(Deno.readTextFileSync(new URL('../../../test/fixtures/order_changes/cancellation_and_product_edit.json',import.meta.url))) as OrderChangeSummary;
for (const lang of ['cs','en'] as const) {
  Deno.test(`canonical cancellation and product edit render distinctly (${lang})`, () => {
    const html=generateChangeOverview(fixture,lang);
    assertStringIncludes(html, lang==='cs' ? 'Stornované vstupenky' : 'Cancelled tickets');
    assertStringIncludes(html,'FIRST');
    assertStringIncludes(html,'SURVIVOR');
    assertEquals(html.includes(lang==='cs' ? 'Odebrané položky' : 'Removed items'),false);
    assertStringIncludes(html,lang==='cs' ? 'Celková cena' : 'Total price');
  });
}
Deno.test('summary renderer escapes ticket symbols and product labels',()=>{
  const value=structuredClone(fixture);
  value.cancelledTickets[0].ticket_symbol='<img src=x onerror=alert(1)>';
  value.cancelledTickets[0].products![0].title='<script>bad</script>';
  const html=generateChangeOverview(value);
  assertEquals(html.includes('<script>'),false);
  assertEquals(html.includes('<img src=x'),false);
  assertStringIncludes(html,'&lt;script&gt;bad&lt;/script&gt;');
});
Deno.test('empty/free cancelled ticket still has a labelled section',()=>{
  const value=structuredClone(fixture);value.cancelledTickets[0].products=[];
  assertStringIncludes(generateChangeOverview(value),'Vstupenka FIRST');
});
Deno.test('unchanged summary renders nothing and missing version fails closed',()=>{
  assertEquals(generateChangeOverview({...fixture,hasChanges:false}),'');
  assertThrows(()=>generateChangeOverview({...fixture,version:2}));
});
Deno.test('product removal on a surviving ticket is never rendered as cancellation',()=>{
  const value=structuredClone(fixture);
  const product=value.cancelledTickets[0].products![0];
  value.cancelledTickets=[];
  value.productChanges=[{id:2,ticket_symbol:'SURVIVOR',added:[],removed:[product],changed:[]}];
  const html=generateChangeOverview(value);
  assertEquals(html.includes('Stornované vstupenky'),false);
  assertStringIncludes(html,'Odebrané položky');
  assertStringIncludes(html,'SURVIVOR');
});
Deno.test('multiple cancellations and mixed product additions/removals keep separate context',()=>{
  const value=structuredClone(fixture);
  value.cancelledTickets.push({id:3,ticket_symbol:'THIRD',products:[]});
  value.productChanges[0].added=[{id:8,title:'New item',price:5}];
  value.productChanges[0].removed=[{id:9,title:'Old item',price:2}];
  const html=generateChangeOverview(value);
  for(const label of ['Vstupenka FIRST','Vstupenka THIRD','Změny produktů na vstupence SURVIVOR','+ New item','- Old item']) assertStringIncludes(html,label);
});
