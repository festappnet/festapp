import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {TicketWalletPage,takeWalletToken,googleWalletSaveUrl} from '../../src/components/ticket_wallet_page.js';
import {readFileSync} from 'node:fs';
function fixture(hash='a'.repeat(64),invoke=async()=>({error:'wallet_unavailable'})) {
 const dom=new JSDOM('<meta name="referrer" content="origin"><div id="host"></div>',{url:'https://tenant.invalid/wallet#'+hash});
 const navigations=[];
 const win={document:dom.window.document,history:dom.window.history,location:{
  get hash(){return dom.window.location.hash;},get pathname(){return dom.window.location.pathname;},
  assign(url){navigations.push(url);},
 }};
 const page=new TicketWalletPage(dom.window.document.getElementById('host'),{win,invoke});return {dom,page,navigations};
}
test('fragment is removed before external scripts; captured token is consumed only in memory',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
 assert(html.indexOf('__festappWalletToken')<html.indexOf('<script src='));
 const {dom}=fixture();assert.equal(takeWalletToken(dom.window),'a'.repeat(64));assert.equal(dom.window.location.hash,'');assert.equal(takeWalletToken(dom.window),null);dom.window.close();
});
test('email link automatically resolves and opens Google Wallet without another click',async()=>{
 let calls=0;const url='https://pay.google.com/gp/v/save/a.b.c';
 const {dom,page,navigations}=fixture('a'.repeat(64),async body=>{
  calls++;assert.equal(body.token,'a'.repeat(64));assert.equal(dom.window.location.hash,'');
  return {state:'ACTIVE',url};
 });
 await page.init();assert.equal(calls,1);assert.deepEqual(navigations,[url]);assert.equal(page.button.hidden,true);dom.window.close();
});
test('automatic resolution supports explicit retry without losing the token',async()=>{
 let calls=0;const {dom,page}=fixture('a'.repeat(64),async body=>{calls++;assert.equal(body.token,'a'.repeat(64));throw new Error('network');});
 await page.init();assert.equal(calls,1);assert.equal(dom.window.location.hash,'');assert.equal(page.status.getAttribute('aria-live'),'polite');
 assert.match(page.status.textContent,/dočasně/);assert.equal(page.button.hidden,false);assert.equal(page.button.disabled,false);assert.equal(page.label.textContent,'Zkusit znovu');
 await page.save();assert.equal(calls,2);page.clear();assert.equal(page.token,null);dom.window.close();
});
test('pending automatic resolution hides the action and prevents concurrent requests',async()=>{
 let resolve,calls=0;const {dom,page}=fixture('a'.repeat(64),()=>{calls++;return new Promise(r=>{resolve=r;});});
 const loading=page.init();assert.equal(page.button.hidden,true);assert.equal(page.button.disabled,true);await page.save();assert.equal(calls,1);
 resolve({error:'wallet_unavailable'});await loading;assert.equal(page.button.hidden,true);dom.window.close();
});
test('missing token and unavailable ticket have clear distinct states',async()=>{
 for(const token of ['', 'invalid', 'a'.repeat(64)]){let calls=0;const {dom,page,navigations}=fixture(token,async()=>{calls++;return {error:'wallet_unavailable'};});await page.init();assert.equal(calls,token.length===64?1:0);assert.equal(page.button.hidden,true);assert.deepEqual(navigations,[]);assert.match(page.status.textContent,token.length===64?/není dostupná/:/znovu otevřete/);dom.window.close();}
});
test('used tickets retain the warning and require explicit continuation',async()=>{
 const url='https://pay.google.com/gp/v/save/a.b.c';const {dom,page,navigations}=fixture('a'.repeat(64),async()=>({state:'COMPLETED',url}));
 await page.init();assert.deepEqual(navigations,[]);assert.match(page.status.textContent,/již byla použita/);assert.equal(page.button.hidden,false);
 page.button.click();assert.deepEqual(navigations,[url]);dom.window.close();
});
test('an unsafe resolver response stays on the retry page without navigating',async()=>{
 const {dom,page,navigations}=fixture('a'.repeat(64),async()=>({state:'ACTIVE',url:'https://evil.invalid/gp/v/save/a.b.c'}));
 await page.init();assert.deepEqual(navigations,[]);assert.equal(page.button.hidden,false);assert.match(page.status.textContent,/dočasně/);dom.window.close();
});
test('Google redirects are constrained to the save origin/path and cannot leak to another site',()=>{
 for(const bad of ['https://evil.invalid/gp/v/save/jwt','https://pay.google.com.evil.invalid/gp/v/save/jwt','javascript:alert(1)','https://pay.google.com/gp/v/save/jwt?redirect=evil','https://evil@pay.google.com/gp/v/save/jwt'])assert.equal(googleWalletSaveUrl(bad),null);
 assert.equal(googleWalletSaveUrl('https://pay.google.com/gp/v/save/a.b.c'),'https://pay.google.com/gp/v/save/a.b.c');
});
