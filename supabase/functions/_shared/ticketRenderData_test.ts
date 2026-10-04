import { assertEquals } from 'jsr:@std/assert@1';
import { normalizeTicketData } from './ticketRenderData.ts';

Deno.test('ticket rendering uses the short product title from the product RPC', () => {
  const ticket = { ticket_symbol: 'TEST', order_product_ticket: [{ id: 1, product: 22 }] };
  const products = { food: { 22: {
    title: 'Steak z panenky se šťouchanými bramborami',
    short_title: 'Steak + brambory',
  } } };
  assertEquals(normalizeTicketData(ticket, {}, {}, products).food, 'Večeře: Steak + brambory');
});

Deno.test('ticket rendering uses stored short titles and falls back to full titles', () => {
  const ticket = { ticket_symbol: 'TEST', order_product_ticket: [{ id: 1, product: 22 }] };
  const product = { title: 'Plný název večeře', data: { short_title: 'Řízek' } };
  const products = { food: { 22: product } };
  assertEquals(normalizeTicketData(ticket, {}, {}, products).food, 'Večeře: Řízek');
  product.data.short_title = '';
  assertEquals(normalizeTicketData(ticket, {}, {}, products).food, 'Večeře: Plný název večeře');
});
