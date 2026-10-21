import { assertEquals, assertRejects } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createTicketFontR2Store } from './ticketFontR2.ts';

const key = `sha256/${'a'.repeat(64)}.ttf`;
const secret = 'dedicated-font-capability-0123456789012345';
Deno.test('R2 font transport preserves bytes and conditional-create outcomes', async () => {
  const replies = [new Response(new Uint8Array([0, 1, 2])), new Response(null, { status: 404 }), new Response(null, { status: 201 }), new Response(null, { status: 409 })];
  const calls: Array<{url:string;init:RequestInit}> = [];
  const request = ((url: string, init: RequestInit) => { calls.push({url,init}); return Promise.resolve(replies.shift()!); }) as typeof fetch;
  const store = createTicketFontR2Store(() => secret, request);
  assertEquals(await store.read(key), new Uint8Array([0, 1, 2]));
  assertEquals(await store.read(key), null);
  assertEquals(await store.create(key, new Uint8Array([3])), true);
  assertEquals(await store.create(key, new Uint8Array([3])), false);
  assertEquals(calls[0].url, `https://image-api.festapp.net/service/ticket-fonts/${key}`);
  assertEquals(calls[0].init.redirect, 'error');
  assertEquals((calls[0].init.headers as Record<string,string>).Authorization, `Bearer ${secret}`);
});
Deno.test('R2 font transport refuses keys, missing secrets, denied and partial reads', async () => {
  const store = createTicketFontR2Store(() => secret, (() => Promise.resolve(new Response(null, {status:403}))) as typeof fetch);
  await assertRejects(() => store.read('../private/x'));
  await assertRejects(() => createTicketFontR2Store(() => undefined).read(key));
  await assertRejects(() => store.read(key));
  await assertRejects(() => store.create(key, new Uint8Array([1])));
  const stream = new ReadableStream({ start(controller) { controller.error(new Error('partial')); } });
  const partial = createTicketFontR2Store(() => secret, (() => Promise.resolve(new Response(stream))) as typeof fetch);
  await assertRejects(() => partial.read(key));
});

Deno.test('R2 transport supports owned local service without relaxing secret or key checks', async () => {
  let called = '';
  const request = ((url: string) => { called = url; return Promise.resolve(new Response(null, {status:404})); }) as typeof fetch;
  const store=createTicketFontR2Store(()=>secret,request,'http://host.lima.internal:59525/service/ticket-fonts/');
  assertEquals(await store.read(key),null);
  assertEquals(called,`http://host.lima.internal:59525/service/ticket-fonts/${key}`);
  for(const endpoint of ['http://example.com/service/ticket-fonts/','https://example.com/arbitrary/','https://user:pass@example.com/service/ticket-fonts/']) {
    let rejected=false;try{createTicketFontR2Store(()=>secret,request,endpoint);}catch{rejected=true;}assertEquals(rejected,true);
  }
});
