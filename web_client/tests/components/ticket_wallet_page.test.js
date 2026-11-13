import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {TicketWalletPage,takeWalletToken} from '../../src/components/ticket_wallet_page.js';
import {googleWalletSaveUrl} from '../../src/components/wallet_connectors.js';
import {readFileSync} from 'node:fs';
function fixture(hash='a'.repeat(64),invoke=async()=>({error:'wallet_unavailable'})) {
 const dom=new JSDOM('<meta name="referrer" content="origin"><div id="host"></div>',{url:'https://tenant.invalid/wallet#'+hash});
 const navigations=[];
 const win={document:dom.window.document,history:dom.window.history,location:{get hash(){return dom.window.location.hash;},get pathname(){return dom.window.location.pathname;},assign(url){navigations.push(url);}}};
 const page=new TicketWalletPage(dom.window.document.getElementById('host'),{win,invoke,walletEndpoint:'https://backend.invalid/functions/v1/ticket-wallet'});return {dom,page,navigations};
}
test('fragment is removed before external scripts and the captured token is consumed only in memory',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');assert(html.indexOf('__festappWalletToken')<html.indexOf('<script src='));
 const {dom}=fixture();assert.equal(takeWalletToken(dom.window),'a'.repeat(64));assert.equal(dom.window.location.hash,'');assert.equal(takeWalletToken(dom.window),null);dom.window.close();
});
test('shared page offers both connectors without issuing either before the user chooses',async()=>{
 let calls=0;const url='https://pay.google.com/gp/v/save/a.b.c';const {dom,page,navigations}=fixture('a'.repeat(64),async body=>{calls++;assert.equal(body.provider,'google');return {state:'ACTIVE',url};});
 await page.init();assert.equal(calls,0);assert.equal(dom.window.location.hash,'');for(const action of page.actions.values())assert.equal(action.button.hidden,false);
 await page.save();assert.equal(calls,1);assert.deepEqual(navigations,[url]);dom.window.close();
});
test('provider failures support explicit retry and concurrent requests cannot issue twice',async()=>{
 let finish,calls=0;const {dom,page}=fixture('a'.repeat(64),()=>{calls++;return new Promise(resolve=>{finish=resolve;});});
 await page.init();const pending=page.save();assert.equal(page.actions.get('google').button.disabled,true);await page.save();assert.equal(calls,1);
 finish({error:'wallet_retry'});await pending;assert.match(page.status.textContent,/dočasně/);assert.equal(page.actions.get('google').button.disabled,false);assert.equal(page.actions.get('apple').button.hidden,false);
 page.clear();assert.equal(page.token,null);dom.window.close();
});
test('missing token and unavailable ticket have distinct states',async()=>{
 for(const token of ['', 'invalid', 'a'.repeat(64)]){const {dom,page,navigations}=fixture(token);await page.init();if(token.length===64)await page.save();for(const action of page.actions.values())assert.equal(action.button.hidden,true);assert.deepEqual(navigations,[]);assert.match(page.status.textContent,token.length===64?/není dostupná/:/znovu otevřete/);dom.window.close();}
});
test('used tickets retain the warning and require explicit continuation',async()=>{
 const url='https://pay.google.com/gp/v/save/a.b.c';const {dom,page,navigations}=fixture('a'.repeat(64),async()=>({state:'COMPLETED',url}));await page.init();await page.save();assert.deepEqual(navigations,[]);assert.match(page.status.textContent,/již byla použita/);page.actions.get('google').button.click();assert.deepEqual(navigations,[url]);dom.window.close();
});
test('unsafe provider URLs stay on the retry page',async()=>{
 const {dom,page,navigations}=fixture('a'.repeat(64),async()=>({state:'ACTIVE',url:'https://evil.invalid/gp/v/save/a.b.c'}));await page.init();await page.save();assert.deepEqual(navigations,[]);assert.match(page.status.textContent,/dočasně/);dom.window.close();
});
test('Google redirects are constrained to the save origin/path',()=>{
 for(const bad of ['https://evil.invalid/gp/v/save/jwt','https://pay.google.com.evil.invalid/gp/v/save/jwt','javascript:alert(1)','https://pay.google.com/gp/v/save/jwt?redirect=evil','https://evil@pay.google.com/gp/v/save/jwt'])assert.equal(googleWalletSaveUrl(bad),null);
 assert.equal(googleWalletSaveUrl('https://pay.google.com/gp/v/save/a.b.c'),'https://pay.google.com/gp/v/save/a.b.c');
});
test('file-delivery connectors submit capability only in a native POST body to the canonical backend',async()=>{
 const {dom,page}=fixture();let submitted=null;
 dom.window.HTMLFormElement.prototype.submit=function(){submitted={url:this.action,method:this.method,values:Object.fromEntries(new dom.window.FormData(this))};};
 await page.init();const apple=page.actions.get('apple');assert.match(apple.button.textContent,/Přidat do Apple Peněženky/);assert.equal(submitted,null);
 page.saveFile(apple.connector);assert.deepEqual(submitted,{url:page.walletEndpoint,method:'post',values:{token:'a'.repeat(64),provider:'apple'}});assert.equal(dom.window.location.hash,'');assert.equal(dom.window.document.querySelector('form'),null);assert.equal(dom.window.localStorage.length,0);
 submitted=null;page.walletEndpoint='javascript:alert(1)';page.saveFile(apple.connector);assert.equal(submitted,null);assert.match(page.status.textContent,/dočasně/);page.clear();page.saveFile(apple.connector);assert.equal(submitted,null);dom.window.close();
});

test('native delivery preserves the trusted Origin while withholding private URL paths',async()=>{
 const {dom,page}=fixture();await page.init();
 assert.equal(dom.window.document.querySelector('meta[name="referrer"]').content,'strict-origin');dom.window.close();
});
test('email-selected file connector starts automatically and uses the email language',async()=>{
 const {dom,page}=fixture();page.win.__festappWalletOptions={provider:'apple',lang:'en'};
 let submits=0;dom.window.HTMLFormElement.prototype.submit=function(){submits++;assert.equal(new dom.window.FormData(this).get('provider'),'apple');};
 await page.init();assert.equal(submits,1);assert.equal(page.locale,'en');assert.equal(page.actions.get('apple').label.textContent,'Add to Apple Wallet');assert.equal(page.win.__festappWalletOptions,undefined);dom.window.close();
});
test('email-selected redirect connector starts automatically without an extra click',async()=>{
 const url='https://pay.google.com/gp/v/save/a.b.c';const {dom,page,navigations}=fixture('a'.repeat(64),async()=>({state:'ACTIVE',url}));
 page.win.__festappWalletOptions={provider:'google',lang:'cs'};await page.init();assert.deepEqual(navigations,[url]);dom.window.close();
});
test('legacy email links on Apple devices start the native connector automatically',async()=>{
 const {dom,page}=fixture();page.win.navigator={userAgent:'Mozilla/5.0 (iPhone; CPU iPhone OS 26_5 like Mac OS X)'};
 let submits=0;dom.window.HTMLFormElement.prototype.submit=function(){submits++;};await page.init();assert.equal(submits,1);dom.window.close();
});

test('Czech Apple action uses Czech text without English artwork; English uses official artwork',async()=>{
 for(const lang of ['cs','en']){
  const {dom,page}=fixture('');page.win.__festappWalletOptions={lang};await page.init();
  const apple=page.actions.get('apple');assert.equal(Boolean(apple.button.querySelector('img')),lang==='en');
  assert.equal(apple.label.textContent,lang==='cs'?'Přidat do Apple Peněženky':'Add to Apple Wallet');dom.window.close();
 }
});

test('early email bootstrap retains only provider and language in memory while removing the capability',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
 const script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
 const dom=new JSDOM('',{url:'https://tenant.invalid/wallet?provider=apple&lang=en#'+'a'.repeat(64),runScripts:'outside-only'});
 dom.window.eval(script);
 assert.equal(dom.window.location.href,'https://tenant.invalid/wallet');
 assert.equal(dom.window.__festappWalletOptions.provider,'apple');assert.equal(dom.window.__festappWalletOptions.lang,'en');
 assert.equal(takeWalletToken(dom.window),'a'.repeat(64));assert.equal(takeWalletToken(dom.window),null);dom.window.close();
});
test('invalid provider and missing capability never trigger automatic issuance',async()=>{
 for(const [token,provider] of [['a'.repeat(64),'unregistered'],['','apple']]){
  let calls=0;const {dom,page}=fixture(token,async()=>{calls++;});page.win.__festappWalletOptions={provider,lang:'invalid'};
  dom.window.HTMLFormElement.prototype.submit=function(){calls++;};await page.init();assert.equal(calls,0);assert.equal(page.locale,'cs');dom.window.close();
 }
});
