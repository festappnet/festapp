import assert from 'node:assert/strict';
import {protectionBinding, protectionConfig, saleOpeningProtection} from './protection.ts';
const config=()=>({siteKey:'public-key',secret:'private-key',hostnames:['vstupenky.online']});
Deno.test('proof is bound to allowed hostname, action and normalized form/contact before admission',async()=>{
 const cdata=await protectionBinding('ples',' JANA@EXAMPLE.COM ');
 const base={success:true,hostname:'vstupenky.online',action:'sale_opening_subscribe',cdata};
 for (const patch of [{},{success:false},{hostname:'evil.invalid'},{action:'login'},{cdata:'another-contact'}]) {
  const guard=saleOpeningProtection(config,async(url,options)=>{
   assert.equal(url,'https://challenges.cloudflare.com/turnstile/v0/siteverify');
   assert.equal(options?.redirect,'error');
   const body=options?.body as URLSearchParams;
   assert.equal(body.get('secret'),'private-key');assert.equal(body.get('response'),'proof');
   assert.equal(body.has('remoteip'),false);
   return Response.json({...base,...patch});
  });
  assert.equal(await guard.verify('proof','ples','jana@example.com'),Object.keys(patch).length===0);
  assert.deepEqual(guard.publicConfig(),{siteKey:'public-key',action:'sale_opening_subscribe'});
 }
});
Deno.test('missing/oversized proofs never call provider and outage fails closed',async()=>{
 let calls=0;
 const guard=saleOpeningProtection(config,async()=>{calls++;throw new Error('offline');});
 for (const token of [undefined,'','x'.repeat(2049),{},42]) assert.equal(await guard.verify(token,'ples','jana@example.com'),false);
 assert.equal(calls,0);
 await assert.rejects(()=>guard.verify('proof','ples','jana@example.com'));
 const bad=saleOpeningProtection(config,async()=>new Response('',{status:503}));
 await assert.rejects(()=>bad.verify('proof','ples','jana@example.com'));
});
Deno.test('spent token is rejected on replay; fresh proof cannot be moved to another form',async()=>{
 let spent=false;
 const guard=saleOpeningProtection(config,async()=>{
  const success=!spent;spent=true;
  return Response.json({success,hostname:'vstupenky.online',action:'sale_opening_subscribe',cdata:await protectionBinding('ples','jana@example.com')});
 });
 assert.equal(await guard.verify('single-use','other-form','jana@example.com'),false);
 assert.equal(await guard.verify('single-use','ples','jana@example.com'),false);
});

Deno.test('missing configuration fails closed and dummy keys are forbidden for live origins',()=>{
 assert.throws(()=>protectionConfig(()=>undefined));
 const env:Record<string,string>={SALE_OPENING_TURNSTILE_SITE_KEY:'1x00000000000000000000AA',SALE_OPENING_TURNSTILE_SECRET_KEY:'dummy',SALE_OPENING_TURNSTILE_HOSTNAMES:'vstupenky.online',SUPABASE_URL:'http://localhost:58321'};
 assert.throws(()=>protectionConfig(key=>env[key]));
 env.SALE_OPENING_TURNSTILE_HOSTNAMES='localhost';env.SUPABASE_URL='https://api.festapp.net';
 assert.throws(()=>protectionConfig(key=>env[key]));
 env.SUPABASE_URL='http://localhost:58321';assert.equal(protectionConfig(key=>env[key]).siteKey,env.SALE_OPENING_TURNSTILE_SITE_KEY);
});
