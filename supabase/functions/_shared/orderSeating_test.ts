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

Deno.test('discount email shows original line prices and one aligned final discounted total', () => {
  const order = {discount:{code:'SLEVA<kod>',base:100,discount:30,net:70,currency:'CZK'}};
  const tickets = [{ticket_symbol:'ABC',products:[{title:'Vstupné',base_price:100,price:70,currency_code:'CZK'}]}];
  const html = generateFullOrder(order,tickets,[],'cs');
  const [items,summary] = html.split('<div class="order-discount-summary"');
  assertStringIncludes(items,'100');
  assertEquals(items.includes('>70'),false);
  assertStringIncludes(summary,'Slevový kód: <strong>SLEVA&lt;kod&gt;</strong>');
  assertStringIncludes(summary,'−30');
  assertStringIncludes(summary,'Cena po slevě');
  assertEquals(summary.includes('Celková cena:'),false);
  assertEquals(tickets[0].products[0].price,70);
});

Deno.test('discount email retains original cancellation facts beside the current zero total', () => {
  const html = generateFullOrder({discount:{code:'SAVE',base:100,discount:30,net:70,currency:'CZK'}},[],[],'cs');
  assertStringIncludes(html,'Původní prodej před stornem');
  assertStringIncludes(html,'Cena po slevě');
  assertStringIncludes(html,'Celková cena: 0');
});

Deno.test('discount email keeps decimal amounts without forcing trailing zeros or double subtraction', () => {
  const html = generateFullOrder({discount:{code:'SAVE',base:100.5,discount:30.25,net:70.25,currency:'CZK'}},[{products:[{base_price:100.5,price:70.25}]}],[],'cs');
  for (const value of ['100,5','−30,25','70,25']) assertStringIncludes(html,value);
  assertEquals(html.includes('100,50'),false);
});
