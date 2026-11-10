import {test} from 'node:test';
import assert from 'node:assert/strict';
import {JSDOM} from 'jsdom';
import {TicketWalletPage,takeWalletToken,googleWalletSaveUrl} from '../../src/components/ticket_wallet_page.js';
import {readFileSync} from 'node:fs';
function fixture(hash='a'.repeat(64),invoke=async()=>({error:'wallet_unavailable'})) {
 const dom=new JSDOM('<meta name="referrer" content="origin"><div id="host"></div>',{url:'https://tenant.invalid/wallet#'+hash});
 const page=new TicketWalletPage(dom.window.document.getElementById('host'),{win:dom.window,invoke});return {dom,page};
}
test('fragment is removed before external scripts; captured token is consumed only in memory',()=>{
 const html=readFileSync(new URL('../../index.html',import.meta.url),'utf8');
 assert(html.indexOf('__festappWalletToken')<html.indexOf('<script src='));
 const {dom}=fixture();assert.equal(takeWalletToken(dom.window),'a'.repeat(64));assert.equal(dom.window.location.hash,'');assert.equal(takeWalletToken(dom.window),null);dom.window.close();
});
test('page makes no network request until explicit user action and supports retry without losing token',async()=>{
 let calls=0;const {dom,page}=fixture('a'.repeat(64),async body=>{calls++;assert.equal(body.token,'a'.repeat(64));throw new Error('network');});
 await page.init();assert.equal(calls,0);assert.equal(dom.window.location.hash,'');assert.equal(page.status.getAttribute('aria-live'),'polite');
 await page.save();assert.equal(calls,1);assert.match(page.status.textContent,/dočasně/);assert.equal(page.button.disabled,false);await page.save();assert.equal(calls,2);page.clear();assert.equal(page.token,null);dom.window.close();
});
test('missing token and unavailable ticket have clear distinct states',async()=>{
 for(const token of ['', 'a'.repeat(64)]){const {dom,page}=fixture(token);await page.init();if(token)await page.save();assert.equal(page.button.hidden,true);assert.match(page.status.textContent,token?/není dostupná/:/znovu otevřete/);dom.window.close();}
});
test('Google redirects are constrained to the save origin/path and cannot leak to another site',()=>{
 for(const bad of ['https://evil.invalid/gp/v/save/jwt','https://pay.google.com.evil.invalid/gp/v/save/jwt','javascript:alert(1)','https://pay.google.com/gp/v/save/jwt?redirect=evil','https://evil@pay.google.com/gp/v/save/jwt'])assert.equal(googleWalletSaveUrl(bad),null);
 assert.equal(googleWalletSaveUrl('https://pay.google.com/gp/v/save/a.b.c'),'https://pay.google.com/gp/v/save/a.b.c');
});
