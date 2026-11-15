import { assertEquals, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { generateFullOrder } from "./orderOverview.ts";
for (const lang of ['cs', 'en'] as const) {
  Deno.test(`order email ${lang} displays table and seat without duplicate product label`, () => {
    const html = generateFullOrder({}, [{ ticket_symbol: 'ABC', products: [{ title: 'Místo', type_title: 'Místo', price: 450, currency_code: 'CZK', spot_group_title: '7', spot_title: '3' }] }], [{code:'ticket',is_enabled:true}], lang);
    assertStringIncludes(html, lang === 'cs' ? 'Stůl: 7 · Místo: 3' : 'Table: 7 · Seat: 3');
    assertEquals(html.includes('Místo: Místo'), false);
  });
}
Deno.test('seating escapes labels and supports ungrouped seats and ordinary products', () => {
  const html = generateFullOrder({}, [{ ticket_symbol: 'ABC', products: [
    {title:'Seat', spot_title:'<b>3</b>', price: 450}, {title:'Lunch',price:100},
  ] }], [], 'en');
  assertStringIncludes(html, 'Seat: &lt;b&gt;3&lt;/b&gt;');
  assertEquals(html.includes('Table:'),false);
  assertStringIncludes(html,'Lunch');
  assertEquals(html.includes('undefined'),false);
});

for (const lang of ['cs', 'en'] as const) {
  Deno.test(`order email ${lang} identifies standing by the actual area name`, () => {
    const html = generateFullOrder({}, [{ticket_symbol:'TEST',products:[{title:'Místo',type_title:'Místo',price:500,currency_code:'CZK',is_standing:true,standing_area_title:'Parket <VIP>'}]}], [], lang);
    assertStringIncludes(html, `${lang === 'cs' ? 'Stání' : 'Standing'}: Parket &lt;VIP&gt;`);
    assertEquals(html.includes('Parket <VIP>'),false);
    assertEquals(html.includes('undefined'),false);
    assertStringIncludes(html,'Místo');
    assertStringIncludes(html,'500');
  });
}
