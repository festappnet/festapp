import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {TicketWalletPage} from '../../src/components/ticket_wallet_page.js';
import {readWalletLink,WalletLinkSession} from '../../src/components/wallet_link.js';
import {spawnSync} from 'node:child_process';
import {googleWalletSaveUrl} from '../../src/components/wallet_connectors.js';
import {readFileSync} from 'node:fs';
function fixture(hash='a'.repeat(64),invoke=async()=>({error:'wallet_unavailable'})) {
 const dom=new JSDOM('<meta name="referrer" content="origin"><div id="host"></div>',{url:'https://tenant.invalid/wallet#'+hash});
 const navigations=[];
 const win={addEventListener:dom.window.addEventListener.bind(dom.window),removeEventListener:dom.window.removeEventListener.bind(dom.window),document:dom.window.document,history:dom.window.history,location:{get hash(){return dom.window.location.hash;},get pathname(){return dom.window.location.pathname;},get search(){return dom.window.location.search;},assign(url){navigations.push(url);}}};
 const page=new TicketWalletPage(dom.window.document.getElementById('host'),{win,invoke,walletEndpoint:'https://backend.invalid/functions/v1/ticket-wallet'});return {dom,page,navigations};
}
test('fragment is removed before external scripts and the captured token is consumed only in memory',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');assert(html.indexOf('__festappWalletToken')<html.indexOf('<script src='));
 const {dom}=fixture();assert.equal(readWalletLink(dom.window).token,'a'.repeat(64));assert.equal(dom.window.location.hash,'');assert.equal(readWalletLink(dom.window).token,null);dom.window.close();
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
 page.save(apple.connector);assert.deepEqual(submitted,{url:page.walletEndpoint,method:'post',values:{token:'a'.repeat(64),provider:'apple'}});assert.equal(dom.window.location.hash,'');assert.equal(dom.window.document.querySelector('form'),null);assert.equal(dom.window.localStorage.length,0);
 submitted=null;page.walletEndpoint='javascript:alert(1)';page.save(apple.connector);assert.equal(submitted,null);assert.match(page.status.textContent,/dočasně/);page.clear();page.save(apple.connector);assert.equal(submitted,null);dom.window.close();
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

test('Apple uses official artwork in each locale with a localized accessible label',async()=>{
 for(const lang of ['cs','en']){
  const {dom,page}=fixture('');page.win.__festappWalletOptions={lang};await page.init();
  const apple=page.actions.get('apple');assert.equal(Boolean(apple.button.querySelector('img')),true);assert(apple.button.classList.contains('wallet-save--badge'));
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
 assert.equal(readWalletLink(dom.window).token,'a'.repeat(64));assert.equal(readWalletLink(dom.window).token,null);dom.window.close();
});
test('invalid provider and missing capability never trigger automatic issuance',async()=>{
 for(const [token,provider] of [['a'.repeat(64),'unregistered'],['','apple']]){
  let calls=0;const {dom,page}=fixture(token,async()=>{calls++;});page.win.__festappWalletOptions={provider,lang:'invalid'};
  dom.window.HTMLFormElement.prototype.submit=function(){calls++;};await page.init();assert.equal(calls,0);assert.equal(page.locale,'cs');dom.window.close();
 }
});

test('reused Safari tabs accept successive legacy links once per navigation and release listeners on clear',async()=>{
 const {dom,page}=fixture();page.win.navigator={userAgent:'iPhone'};const submitted=[];
 dom.window.HTMLFormElement.prototype.submit=function(){submitted.push(new dom.window.FormData(this).get('token'));};
 await page.init();
 for(const token of ['b'.repeat(64),'b'.repeat(64)]){
  dom.window.history.replaceState(null,'','/wallet#'+token);
  dom.window.dispatchEvent(new dom.window.PopStateEvent('popstate'));
  dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));
  assert.equal(dom.window.location.hash,'');
 }
 assert.deepEqual(submitted,['a'.repeat(64),'b'.repeat(64),'b'.repeat(64)]);
 page.clear();dom.window.history.replaceState(null,'','/wallet#'+'c'.repeat(64));dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));
 assert.equal(submitted.length,3);assert.equal(page.host.childElementCount,0);dom.window.close();
});
test('a late Google response cannot redirect or replace the status of a subsequently opened Apple ticket',async()=>{
 let finish;const {dom,page,navigations}=fixture('a'.repeat(64),()=>new Promise(resolve=>{finish=resolve;}));
 page.win.__festappWalletOptions={provider:'google',lang:'cs'};const pending=page.init();
 let submitted=null;dom.window.HTMLFormElement.prototype.submit=function(){submitted=new dom.window.FormData(this).get('token');};
 page.win.__festappWalletOptions={provider:'apple',lang:'en'};dom.window.history.replaceState(null,'','/wallet#'+'b'.repeat(64));dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));
 finish({state:'ACTIVE',url:'https://pay.google.com/gp/v/save/a.b.c'});await pending;
 assert.equal(submitted,'b'.repeat(64));assert.deepEqual(navigations,[]);assert.match(page.status.textContent,/If Wallet opened/);assert.equal(page.locale,'en');dom.window.close();
});

test('leaving the Wallet route cancels pending work without consuming another route fragment',async()=>{
 let finish,signal;const {dom,page,navigations}=fixture('a'.repeat(64),(_body,options)=>{signal=options.signal;return new Promise(resolve=>{finish=resolve;});});
 page.win.__festappWalletOptions={provider:'google'};const pending=page.init();
 dom.window.history.replaceState(null,'','/order?keep=true#'+'b'.repeat(64));dom.window.dispatchEvent(new dom.window.PopStateEvent('popstate'));
 assert.equal(signal.aborted,true);assert.equal(dom.window.location.search,'?keep=true');assert.equal(dom.window.location.hash,'#'+'b'.repeat(64));
 finish({state:'ACTIVE',url:'https://pay.google.com/gp/v/save/a.b.c'});await pending;assert.deepEqual(navigations,[]);page.clear();dom.window.close();
});

test('the shared page dispatches an installed file connector without provider-specific branches',async()=>{
 const {dom,page}=fixture();page.connectors=[{id:'third',delivery:'file',label:()=> 'Uložit vstupenku',badge:()=>undefined,matchesDevice:()=>true}];
 let submitted;dom.window.HTMLFormElement.prototype.submit=function(){submitted=Object.fromEntries(new dom.window.FormData(this));};
 await page.init();assert.deepEqual(submitted,{token:'a'.repeat(64),provider:'third'});page.clear();dom.window.close();
});
test('restored-page input is consumed once and invalid replacement cannot reuse the previous capability',async()=>{
 const {dom,page}=fixture();page.win.navigator={userAgent:'iPhone'};let calls=0;
 dom.window.HTMLFormElement.prototype.submit=function(){calls++;};await page.init();
 dom.window.dispatchEvent(new dom.window.PageTransitionEvent('pageshow',{persisted:true}));assert.equal(calls,1);
 dom.window.history.replaceState(null,'','/wallet#'+'b'.repeat(64));dom.window.dispatchEvent(new dom.window.PageTransitionEvent('pageshow',{persisted:true}));assert.equal(calls,2);
 dom.window.history.replaceState(null,'','/wallet#invalid');dom.window.dispatchEvent(new dom.window.HashChangeEvent('hashchange'));assert.equal(calls,2);assert.equal(page.token,null);assert.equal(dom.window.location.hash,'');
 for(const action of page.actions.values())assert.equal(action.button.hidden,true);page.clear();dom.window.close();
});

test('link completion preserves awaited errors and ignored browser-event work cannot reject unhandled',async()=>{
 const {dom,page}=fixture();const session=new WalletLinkSession(dom.window);const warn=console.warn;
 console.warn=()=>{};
 try{await assert.rejects(session.start(async()=>{throw new Error('receiver failed');}),/receiver failed/);}finally{session.dispose();console.warn=warn;dom.window.close();}
 const moduleUrl=new URL('../../src/components/wallet_link.js',import.meta.url).href;
 const script=`import {WalletLinkSession} from ${JSON.stringify(moduleUrl)};
  const target=new EventTarget();const location={pathname:'/wallet',search:'',hash:'#'+'a'.repeat(64)};
  const win={location,history:{replaceState(){location.hash='';}},addEventListener:target.addEventListener.bind(target),removeEventListener:target.removeEventListener.bind(target)};
  console.warn=()=>{};let unhandled=0;process.on('unhandledRejection',()=>{unhandled++;});
  const session=new WalletLinkSession(win);session.start(async()=>{throw new Error('ignored initial failure');});
  location.hash='#'+'b'.repeat(64);target.dispatchEvent(new Event('hashchange'));
  setImmediate(()=>{session.dispose();if(unhandled)process.exitCode=1;else process.stdout.write('no-unhandled-rejection');});`;
 const child=spawnSync(process.execPath,['--input-type=module','-e',script],{encoding:'utf8'});
 assert.equal(child.status,0,child.stderr);assert.equal(child.stdout,'no-unhandled-rejection');
});

test('collection Apple action plans once and submits all scoped tickets natively without another click',async()=>{
 const plan={kind:'collection',revision:'b'.repeat(64),ticketCount:3,originalCount:3,parts:[3],state:'ACTIVE'};
 const calls=[];const {dom,page}=fixture('a'.repeat(64),async body=>{calls.push(body);return plan;});
 page.win.__festappWalletOptions={provider:'apple',scope:'collection',lang:'cs'};
 let submitted;dom.window.HTMLFormElement.prototype.submit=function(){submitted=Object.fromEntries(new dom.window.FormData(this));};
 await page.init();assert.equal(calls.length,1);assert.equal(calls[0].action,'plan');
 assert.deepEqual(submitted,{token:'a'.repeat(64),provider:'apple',revision:plan.revision,part:'0'});
 assert.match(page.host.textContent,/Uložení vstupenek/);assert.match(page.host.textContent,/Dostupných vstupenek: 3/);assert(!page.host.textContent.includes('uloženy'));
 dom.window.close();
});
test('a partial collection warns before delivery; multiple parts remain individually available',async()=>{
 const plan={kind:'collection',revision:'b'.repeat(64),ticketCount:11,originalCount:12,parts:[10,1],state:'ACTIVE'};
 const {dom,page}=fixture('a'.repeat(64),async()=>plan);page.win.__festappWalletOptions={provider:'apple',scope:'collection'};
 const submitted=[];dom.window.HTMLFormElement.prototype.submit=function(){submitted.push(Object.fromEntries(new dom.window.FormData(this)));};
 await page.init();assert.equal(submitted.length,0);assert.match(page.status.textContent,/Některé vstupenky/);
 const action=page.actions.get('apple');assert.equal(action.parts.querySelectorAll('button').length,2);
 await page.save(action.connector,1);assert.equal(submitted.length,1);assert.equal(submitted[0].part,'1');dom.window.close();
});
test('collection Google action issues a reference-only planned part; a stale plan can be retried',async()=>{
 const plan={kind:'collection',revision:'b'.repeat(64),ticketCount:3,originalCount:3,parts:[3],state:'ACTIVE'};
 const calls=[];const url='https://pay.google.com/gp/v/save/a.b.c';
 const {dom,page,navigations}=fixture('a'.repeat(64),async body=>{calls.push(body);return body.action==='plan'?plan:{state:'ACTIVE',url};});
 page.win.__festappWalletOptions={provider:'google',scope:'collection'};await page.init();
 assert.deepEqual(calls.map(call=>call.action??'issue'),['plan','issue']);assert.equal(calls[1].revision,plan.revision);assert.equal(calls[1].part,0);assert.deepEqual(navigations,[url]);dom.window.close();
});

test('native collection download gives conditional completion guidance rather than claiming Wallet opened',async()=>{
 const plan={kind:'collection',revision:'b'.repeat(64),ticketCount:2,originalCount:2,parts:[2],state:'ACTIVE'};
 const {dom,page}=fixture('a'.repeat(64),async()=>plan);page.win.__festappWalletOptions={provider:'apple',scope:'collection'};
 let downloads=0;dom.window.HTMLFormElement.prototype.submit=function(){downloads++;};
 await page.init();assert.equal(downloads,1);
 assert.match(page.status.textContent,/Pokud se soubor pouze stáhl/);assert.match(page.status.textContent,/Safari na iPhonu/);
 assert(!page.status.textContent.includes('Skupina 1'));assert(!page.status.textContent.includes('byla nabídnuta'));
 assert.equal(page.summary.textContent,'Dostupných vstupenek: 2.');
 const main=page.host.querySelector('main');assert([...main.children].indexOf(page.summary)<[...main.children].indexOf(main.querySelector('.wallet-actions')));
 for(const {button,label} of page.actions.values()){
  assert(button.classList.contains('wallet-save--badge'));assert(label.classList.contains('wallet-label'));
  assert.equal(button.querySelectorAll('img').length,1);
  const img=button.querySelector('img');img.dispatchEvent(new dom.window.Event('error'));
  assert.equal(img.hidden,true);assert.equal(button.classList.contains('wallet-save--badge'),false);
 }
 dom.window.close();
});
test('failed native submission retains retry feedback instead of replacing it with success instructions',async()=>{
 const plan={kind:'collection',revision:'b'.repeat(64),ticketCount:2,originalCount:2,parts:[2],state:'ACTIVE'};
 const {dom,page}=fixture('a'.repeat(64),async()=>plan);page.win.__festappWalletOptions={provider:'apple',scope:'collection'};
 dom.window.HTMLFormElement.prototype.submit=function(){throw new Error('download blocked');};
 await page.init();assert.match(page.status.textContent,/dočasně nedostupná/);assert(!page.status.textContent.includes('Pokud se soubor'));dom.window.close();
});
