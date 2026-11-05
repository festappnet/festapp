import {readFileSync} from 'node:fs';
import {webcrypto} from 'node:crypto';
import test from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
const source=readFileSync(new URL('../../../web/festapp_sale_opening_protection.js',import.meta.url),'utf8');
function browser(api){
 const dom=new JSDOM('<head></head><body></body>',{url:'https://vstupenky.online/form/ples',runScripts:'outside-only'});
 Object.defineProperty(dom.window,'crypto',{value:webcrypto});dom.window.TextEncoder=TextEncoder;
 dom.window.turnstile=api;dom.window.eval(source);return dom;
}
test('normal check uses interaction-only mode, bound proof and cleans up after each attempt',async()=>{
 let removed=0;const options=[];
 const dom=browser({render:(host,o)=>{options.push(o);setTimeout(()=>o.callback('one-use-token'),0);return 'widget';},remove:id=>{assert.equal(id,'widget');removed++;}});
 try{
  const verify=dom.window.FestappSaleOpeningProtection.verify;
  assert.equal(await verify('public','ples',' JANA@EXAMPLE.COM '),'one-use-token');
  assert.equal(options[0].appearance,'interaction-only');assert.equal(options[0].action,'sale_opening_subscribe');
  const digest=Buffer.from(await webcrypto.subtle.digest('SHA-256',new TextEncoder().encode(JSON.stringify(['ples','jana@example.com'])))).toString('hex');
  assert.equal(options[0].cData,digest);assert.equal(removed,1);assert.equal(dom.window.document.body.children.length,0);
  await verify('public','ples','jana@example.com');assert.equal(removed,2);
 }finally{dom.window.close();}
});
test('failed and expired checks reject without leaving a widget behind',async()=>{
 for (const event of ['error-callback','expired-callback','timeout-callback']) {
  let removed=0;const dom=browser({render:(host,o)=>{setTimeout(()=>o[event](),0);return 'widget';},remove:()=>{removed++;}});
  try{await assert.rejects(()=>dom.window.FestappSaleOpeningProtection.verify('public','ples','jana@example.com'));assert.equal(removed,1);assert.equal(dom.window.document.body.children.length,0);}finally{dom.window.close();}
 }
});
test('client never posts subscription when protection fails, successful retry obtains a new token',async()=>{
 const {saleOpeningCommand}=await import('../../src/components/forms/sale_opening_notifications.js');
 let verifications=0;const requests=[];
 const previous=globalThis.window;
 globalThis.window={FestappSaleOpeningProtection:{verify:async()=>{verifications++;if(verifications===1)throw Error('blocked');return 'fresh-token';}}};
 const client={functions:{invoke:async(name,{body})=>{requests.push(body);return {data:body.operation==='protection'?{ok:true,siteKey:'public'}:{ok:true},error:null};}}};
 try{
  await assert.rejects(()=>saleOpeningCommand('subscribe',{formLink:'ples',email:'jana@example.com',lang:'cs'},client));
  assert.deepEqual(requests.map(r=>r.operation),['protection']);
  await saleOpeningCommand('subscribe',{formLink:'ples',email:'jana@example.com',lang:'cs'},client);
  assert.deepEqual(requests.map(r=>r.operation),['protection','protection','subscribe']);
  assert.equal(requests[2].botToken,'fresh-token');
 }finally{globalThis.window=previous;}
});
test('both app bundles ship the same adapter',()=>{
 assert.equal(source,readFileSync(new URL('../../public/festapp_sale_opening_protection.js',import.meta.url),'utf8'));
});

test('provider diagnostics expose only bounded error codes, never contacts or token-like values',async()=>{
 for (const [input,expected] of [['110200','110200'],['600010','600010'],['private-token-or-contact','unavailable']]) {
  const dom=browser({render:(host,o)=>{setTimeout(()=>o['error-callback'](input),0);return 'widget';},remove:()=>{}});
  try{
   const diagnostics=[];dom.window.addEventListener('festapp-sale-opening-verification-error',e=>diagnostics.push(e.detail));
   await assert.rejects(()=>dom.window.FestappSaleOpeningProtection.verify('public','ples','jana@example.com'));
   assert.equal(JSON.stringify(diagnostics),JSON.stringify([{code:expected}]));
  }finally{dom.window.close();}
 }
});
