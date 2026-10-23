import {assertEquals,assertRejects,assertThrows} from 'jsr:@std/assert@1';
import {createTicketBatchR2Store} from './ticketBatchR2.ts';
const key=`ba000000-0000-0000-0000-000000000001/${'a'.repeat(64)}/single-001.pdf`;
const secret='batch-only-private-service-capability-0123456789';
Deno.test('private batch transport preserves bytes and immutable replay without any Storage API',async()=>{
 const calls:any[]=[];const bytes=new Uint8Array([37,80,68,70]);
 const store=createTicketBatchR2Store(()=>secret,async(url,init)=>{calls.push({url,init});return init?.method==='PUT'?new Response(null,{status:calls.length===1?201:409}):new Response(bytes);});
 await store.create(key,bytes,'application/pdf');await store.create(key,bytes,'application/pdf');assertEquals(await store.read(key),bytes);
 assertEquals(calls[0].init.redirect,'error');assertEquals(calls[0].init.headers.Authorization,`Bearer ${secret}`);
 assertEquals(calls[0].url,'https://image-api.festapp.net/service/ticket-batches/'+key);
});
Deno.test('private batch transport fails closed for absent secrets, malformed keys, remote redirects and failed reads',async()=>{
 assertThrows(()=>createTicketBatchR2Store(()=>secret,fetch,'http://foreign.invalid/service/ticket-batches/'));
 const store=createTicketBatchR2Store(()=>secret,async()=>new Response(null,{status:403}));
 await assertRejects(()=>store.read('../private/file'));await assertRejects(()=>store.read(key));
 await assertRejects(()=>createTicketBatchR2Store(()=>undefined).read(key));
 assertEquals(await createTicketBatchR2Store(()=>secret,async()=>new Response(null,{status:404})).read(key),null);
});
