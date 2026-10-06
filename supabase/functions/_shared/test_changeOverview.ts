import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { generateChangeOverview } from "./changeOverview.ts";

Deno.test('ticket cancellation reports one removal for two identical tickets', () => {
  const product = {id: 7, title: 'Vstupenka', price: 100, currency_code: 'CZK'};
  const original = {tickets: [{id: 1, products: [product]}, {id: 2, products: [product]}]};
  const current = {tickets: [{id: 2, products: [product]}]};
  const html = generateChangeOverview(current, original);
  assertStringIncludes(html, 'Odebrané položky');
  assertEquals((html.match(/- Vstupenka/g) ?? []).length, 1);
  assertEquals(html.includes('Přidané položky'), false);
  assertStringIncludes(html, 'Celková cena');
});
