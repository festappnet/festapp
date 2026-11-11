#!/usr/bin/env node
import {timed} from './test_timings.mjs';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import path from 'node:path';
import {createServer} from 'vite';
import {createNativeBrowser} from './native_browser.mjs';
let cmp = process.argv.includes('--cmp');
const modes = process.argv.includes('--both') ? [false, true] : [cmp];
const liveGtm = process.argv.includes('--live-gtm');
const root=path.resolve(import.meta.dirname,'..');
let host, child, childB, context, page;
const owner=await createNativeBrowser({externalOrigins:liveGtm ? ['https://www.googletagmanager.com'] : []});
try {
 child=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-child',configureServer(s){s.middlewares.use((req,res,next)=>{if(req.url==='/form/consent-link'){res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><main></main><script type="module" src="/tests/fixtures/form_measurement/consent_link_child.js"></script></body></html>');return}if(!req.url.startsWith('/form/test'))return next();res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><script type="module" src="/tests/fixtures/form_measurement/child.js"></script></body></html>')})}}]});
 await timed('browser.server-start', () => child.listen(), {suite: 'form_measurement_browser'}); const childOrigin=`http://127.0.0.1:${child.httpServer.address().port}`;
 childB=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-child-b',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><script type="module" src="/tests/fixtures/form_measurement/child.js"></script></body></html>')})}}]});
 await timed('browser.server-start', () => childB.listen(), {suite: 'form_measurement_browser'});const childBOrigin=`http://127.0.0.1:${childB.httpServer.address().port}`;
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-host',configureServer(s){s.middlewares.use((req,res,next)=>{if(req.url==='/consent-link'){res.setHeader('Content-Type','text/html; charset=utf-8');res.end(`<!doctype html><a data-festapp-consent-link target="_blank" href="${childOrigin}/form/consent-link">Buy tickets</a><script>window.dataLayer=[];function gtag(){dataLayer.push(arguments)}gtag('consent','update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'})</script><script src="${childOrigin}/embed.js"></script><script>window.linkSourceListeners=new Set();window.linkSourceChoice={processingRevision:"link-browser",analytics:true,marketing:true};window.stopLinkSource=FestappEmbed.connectMeasurementSource({read:scope=>scope.organization===1\u0026\u0026scope.unit===2?window.linkSourceChoice:null,subscribe:fn=>{linkSourceListeners.add(fn);return()=>linkSourceListeners.delete(fn)}});window.updateLinkSource=choice=>{window.linkSourceChoice=choice;for(const fn of linkSourceListeners)fn()};</script>`);return}if(req.url.startsWith('/consent-link-cmp')) {
const state=new URL(req.url,'http://fixture').searchParams.get('state')||'saved';
res.setHeader('Content-Type','text/html; charset=utf-8');
res.end(`<!doctype html><a data-festapp-consent-link target="_blank" href="${childOrigin}/form/consent-link">Buy tickets</a>
<script type="module">
import {complianzFixture,complianzConfig} from '/tests/support/complianz_fixture.js';
const state=${JSON.stringify(state)};
const choice=['undecided','none','gcm-default','gcm-update'].includes(state)?null:{analytics:state!=='denied',marketing:state!=='denied'};
const cmp=complianzFixture(window,{choice,cookiePath:'/consent-link-cmp'});window.fixtureChoose=cmp.choose;
if(state==='none')delete window.cmplz_has_consent;
if(state==='forced-statistics')complianz.forceEnableStats=1;
if(state==='policy-changed')complianz.current_policy_id='43';
if(state.startsWith('gcm-')){window.dataLayer=[];window.gtag=function(){dataLayer.push(arguments)};gtag('consent',state==='gcm-default'?'default':'update',{analytics_storage:'granted',ad_storage:'granted',ad_user_data:'granted',ad_personalization:'granted'});}
const script=document.createElement('script');script.src=${JSON.stringify(childOrigin)}+'/embed.js';
if(!state.startsWith('gcm-'))script.setAttribute('data-festapp-consent',JSON.stringify({...complianzConfig,...(state==='scope-changed'?{consentRevision:'b'.repeat(32)}:{})}));
document.head.appendChild(script);
</script>`);return;
}if(req.url==='/cmp/klaro.js'){res.setHeader('Content-Type','application/javascript; charset=utf-8');readFile(path.join(root,'node_modules/klaro/dist/klaro.js')).then(value=>res.end(value));return}if(req.url==='/away'){res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><title>Away</title>');return}if(!['/','/?private=1'].includes(req.url) && !(cmp && req.url.startsWith('/?cmp=1')))return next();const privateEntry=req.url.includes('private=1');res.setHeader('Content-Type','text/html; charset=utf-8');res.end(`<!doctype html><html><head><meta charset="utf-8"></head><body><iframe data-festapp-embed data-festapp-datalayer src="${childOrigin}/form/test?embed=1${privateEntry?'&token=private#secret':''}"></iframe><script>window.addEventListener('pageshow',e=>sessionStorage.setItem('fixture-pageshow',JSON.stringify({persisted:e.persisted,navigation:performance.getEntriesByType('navigation')[0]?.type})));window.heartbeats=new Set();const fixtureSetInterval=window.setInterval,fixtureClearInterval=window.clearInterval;window.setInterval=(fn,ms,...args)=>{const id=fixtureSetInterval(fn,ms,...args);if(ms===20000)heartbeats.add(id);return id};window.clearInterval=id=>{heartbeats.delete(id);return fixtureClearInterval(id)};window.fixtureReadyCount=0;window.dataLayer=[];window.replies=new Map();window.addEventListener('message',e=>{if(e.data?.fixtureReady)fixtureReadyCount++;if(e.data?.fixtureReply){const f=window.replies.get(e.data.id);if(f){window.replies.delete(e.data.id);f(e.data)}}});window.call=(action,arg)=>new Promise((resolve,reject)=>{const id=crypto.randomUUID();window.replies.set(id,r=>r.error?reject(Error(r.error)):resolve(r.result));document.querySelector('iframe').contentWindow.postMessage({fixture:true,id,action,arg},'*');setTimeout(()=>reject(Error('fixture timeout '+action)),5000)});</script><script src="/embed.js"></script>${cmp?'<script>window.fixtureErrors=[];window.addEventListener("error",e=>fixtureErrors.push({message:e.message,source:e.filename,line:e.lineno,target:e.target?.src}),true)</script><script src="/cmp/klaro.js" onload="window.klaroLoaded=true" onerror="window.klaroLoaded=false"></script><script src="/tests/fixtures/form_measurement/klaro_host.js"></script>':''}</body></html>`)})}}]});
 await timed('browser.server-start', () => host.listen(), {suite: 'form_measurement_browser'}); const origin=`http://127.0.0.1:${host.httpServer.address().port}`;
 owner.allow(origin); owner.allow(childOrigin); owner.allow(childBOrigin);
 if (modes.includes(true)) await timed('browser.consent-link', async () => {
  const linkContext=await owner.context();
  try {
   const organizer=await linkContext.newPage();await organizer.goto(`${origin}/consent-link`);
   await organizer.waitForFunction('!!window.FestappEmbed');
   const popupReady=organizer.waitForEvent('popup');await organizer.locator('a').click();const popup=await popupReady;
   await popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   assert.deepEqual(await popup.evaluate(()=>({analytics:linkChoices.at(-1).analytics,marketing:linkChoices.at(-1).marketing})),{analytics:true,marketing:true});
   assert.equal(await popup.evaluate(()=>Number.isFinite(linkChoices.at(-1).expiresAt) && typeof linkChoices.at(-1).leaseId==='string'),true);
   assert.equal(await popup.locator('.cookie-modal-notice').count(),0);
   assert.equal(await popup.evaluate(()=>window.opener),null);
   assert.equal(await popup.locator('[data-festapp-consent-imported]').count(),0);
   await popup.locator('.festapp-consent-fab').click();
   await popup.locator('.cm-modal').waitFor({state:'visible'});
   await popup.keyboard.press('Escape');
   await popup.waitForFunction(() => document.activeElement?.matches('.festapp-consent-fab'));
   assert.equal(await popup.evaluate(()=>document.cookie), '');
   // Live source withdrawal changes the current visit without saving cookies.
   await organizer.evaluate(()=>updateLinkSource({processingRevision:'link-browser',analytics:false,marketing:false}));
   await popup.waitForFunction(()=>linkChoices.at(-1)?.analytics===false && linkChoices.at(-1)?.marketing===false);
   await organizer.evaluate(()=>updateLinkSource({processingRevision:'link-browser',analytics:true,marketing:true}));
   await popup.waitForFunction(()=>linkChoices.at(-1)?.analytics===true && linkChoices.at(-1)?.marketing===true);
   await organizer.evaluate(()=>stopLinkSource());
   await popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
   assert.equal(await popup.evaluate(()=>linkChoices.at(-1)?.analytics || linkChoices.at(-1)?.marketing),false);
   const direct=await linkContext.newPage();
   await direct.goto(`${childOrigin}/form/consent-link`,{referer:`${origin}/consent-link`});
   await direct.locator('.cookie-modal-notice').waitFor({state:'visible'});
   assert.equal(await direct.evaluate(()=>linkChoices.some(c=>c?.analytics || c?.marketing)),false);
   await direct.close();
   await popup.reload();
   await popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
   assert.equal(await popup.evaluate(()=>linkChoices.some(c=>c?.analytics || c?.marketing)),false);
   await popup.locator('.cn-decline').click();
   await popup.waitForFunction('linkChoices.at(-1)?.analytics===false && linkChoices.at(-1)?.marketing===false');
   assert.equal(await popup.locator('[data-festapp-consent-imported]').count(),0);
   assert.equal(await popup.evaluate(()=>document.cookie.includes('-source=')),false);
   await popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   await popup.reload();await popup.waitForFunction('window.linkChoices?.length>0');
   assert.deepEqual(await popup.evaluate(()=>linkChoices.at(-1)),{analytics:false,marketing:false});
  } finally {await linkContext.close();}
 }, {suite:'form_measurement_browser',scenario:'consent-link'});
 if (modes.includes(true)) await timed('browser.consent-link-cmp', async () => {
  const linkContext=await owner.context();
  try {
   const open=async query=>{const organizer=await linkContext.newPage();await organizer.goto(`${origin}/consent-link-cmp${query}`);await organizer.waitForFunction('!!window.FestappEmbed');
    const popupReady=organizer.waitForEvent('popup');await organizer.locator('a').click();return {organizer,popup:await popupReady}};
   // Configured Complianz saved choice is imported through the real helper.
   const {organizer,popup}=await open('');
   await popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   assert.deepEqual(await popup.evaluate(()=>({analytics:linkChoices.at(-1).analytics,marketing:linkChoices.at(-1).marketing})),{analytics:true,marketing:true});
   assert.equal(await popup.locator('.cookie-modal-notice').count(),0);
   assert.equal(await popup.evaluate(()=>document.cookie),'');
   // Withdrawal in the website CMP reaches the open form live.
   await organizer.evaluate(()=>fixtureChoose({marketing:false}));
   await popup.waitForFunction(()=>linkChoices.at(-1)?.analytics===true && linkChoices.at(-1)?.marketing===false);
   await organizer.evaluate(()=>fixtureChoose({analytics:false}));
   await popup.waitForFunction(()=>linkChoices.at(-1)?.analytics===false && linkChoices.at(-1)?.marketing===false);
   // Closing the website ends the import; the form asks locally.
   await organizer.close();
   await popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
   assert.equal(await popup.evaluate(()=>linkChoices.at(-1)?.analytics || linkChoices.at(-1)?.marketing),false);
   await popup.close();
   // A website reload or navigation ends the import at once (Complianz reloads after a revoke).
   const reloaded=await open('');
   await reloaded.popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   await reloaded.organizer.reload();
   await reloaded.popup.locator('.cookie-modal-notice').waitFor({state:'visible',timeout:5000});
   assert.equal(await reloaded.popup.evaluate(()=>linkChoices.at(-1)?.analytics || linkChoices.at(-1)?.marketing),false);
   await reloaded.popup.close();await reloaded.organizer.close();
   // A changed processing scope mid-visit ends the import and never re-imports.
   for (const policy of [{processing_revision:'link-browser-2'},{measurement_consent_bridge:false,processing_revision:'link-browser-3'},{approved_hosts:['https://other.example'],processing_revision:'link-browser-4'}]) {
    const scoped=await open('');
    await scoped.popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
    assert.equal(await scoped.popup.evaluate(()=>linkChoices.at(-1).analytics && linkChoices.at(-1).marketing),true);
    await scoped.popup.evaluate(policy=>changeLinkScope(policy),policy);
    await scoped.popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
    assert.deepEqual(await scoped.popup.evaluate(()=>({analytics:linkChoices.at(-1).analytics,marketing:linkChoices.at(-1).marketing})),{analytics:false,marketing:false},JSON.stringify(policy));
    await scoped.organizer.evaluate(()=>{fixtureChoose({analytics:false});fixtureChoose({analytics:true})});
    await scoped.popup.waitForTimeout(1500);
    assert.equal(await scoped.popup.evaluate(()=>linkChoices.some((c,i)=>i>=linkChoices.length-3 && (c?.analytics||c?.marketing))),false,'no re-import under the new scope');
    assert.equal(await scoped.popup.evaluate(()=>document.cookie),'');
    await scoped.popup.close();await scoped.organizer.close();
   }
   // A saved choice is restored by the CMP independently of Consent Mode.
   const saved=await open('?state=saved');
   await saved.popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   assert.deepEqual(await saved.popup.evaluate(()=>({analytics:linkChoices.at(-1).analytics,marketing:linkChoices.at(-1).marketing})),{analytics:true,marketing:true});
   assert.equal(await saved.popup.locator('.cookie-modal-notice').count(),0);
   await saved.popup.close();await saved.organizer.close();
   // Saved refusal transfers without another banner; unknown state stays local.
   const denied=await open('?state=denied');
   await denied.popup.locator('.festapp-consent-fab').waitFor({state:'visible'});
   assert.deepEqual(await denied.popup.evaluate(()=>({analytics:linkChoices.at(-1).analytics,marketing:linkChoices.at(-1).marketing})),{analytics:false,marketing:false});
   assert.equal(await denied.popup.locator('.cookie-modal-notice').count(),0);
   await denied.popup.close();await denied.organizer.close();
   // No saved response: the form asks.
   const undecided=await open('?state=undecided');
   await undecided.popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
   assert.equal(await undecided.popup.evaluate(()=>linkChoices.some(c=>c?.analytics || c?.marketing)),false);
   await undecided.popup.close();await undecided.organizer.close();
   for(const state of ['none','gcm-default','gcm-update','forced-statistics','policy-changed','scope-changed']) {
    const invalid=await open('?state='+state);
    await invalid.popup.locator('.cookie-modal-notice').waitFor({state:'visible'});
    assert.equal(await invalid.popup.evaluate(()=>linkChoices.some(c=>c?.analytics || c?.marketing)),false,state);
    await invalid.popup.close();await invalid.organizer.close();
   }
  } finally {await linkContext.close();}
 }, {suite:'form_measurement_browser',scenario:'consent-link-cmp'});
 for (cmp of modes) {
  try {
   await timed('browser.scenario', async () => {
 context=await owner.context();page=await context.newPage();await owner.setTopLevelColorScheme(page,'light');
 await page.goto(cmp?`${origin}/?cmp=1${liveGtm?'&live-gtm=1':''}`:origin); await page.waitForFunction('!!window.FestappEmbed && !!document.querySelector("iframe")');
 const run=code=>page.evaluate(`(async()=>{${code}})()`);
 await page.waitForFunction('window.call && document.querySelector("iframe")');
 let state;const until=async(test,label)=>{for(let i=0;i<120;i++){state=await run("return await call('state')");if(state&&test(state))return;await new Promise(r=>setTimeout(r,50))}assert.fail(label+': '+JSON.stringify(state))};
 await until(s=>s.instance,'layout bridge initialized');await until(s=>s.state==='active','a helper alone activates without any consent source');
 await run("await call('view');return true");await page.waitForFunction("dataLayer.some(x=>x.event==='form_page_view')");
 await run("FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),true);return true");await new Promise(r=>setTimeout(r,150));assert.equal((await run("return await call('state')")).state,'active','a choice never stops measurement');
 if(cmp){await page.waitForFunction('!!window.cmpManager || !!window.cmpFailure');assert.equal(await run('return cmpFailure'),null);await run("window.disconnect=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),cmpSource);return true");await run("cmpChoose(true,false);return true");await until(s=>s.consent?.analytics===true && s.consent?.marketing===false,'one purpose is reported as state');await run("cmpChoose(true,true);return true");await until(s=>s.consent?.marketing===true,'both purposes are reported as state');}
 else {await run("window.choice=null;window.notify=null;window.disconnect=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>choice,subscribe:n=>{notify=n;return ()=>notify=null}});return true");await run("choice={processingRevision:'rev-a',analytics:true,marketing:true};notify();return true");await until(s=>s.consent?.marketing===true,'a source reports the saved choice');}
 assert.equal(state.state,'active');await run('dataLayer.length=0;return true');
 const purchase={event:'purchase',email:'private@example.test',user_data:{email:'visitor@example.test',phone_number:'+420601234567',first_name:'private'},ecommerce:{currency:'CZK',transaction_id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',payment_type:'card',items:[{item_id:'product_1',item_name:'Ticket',price:10,quantity:1,email:'private@example.test'}]}};
 await run(`await call('raw',${JSON.stringify(purchase)});return true`);await page.waitForFunction("dataLayer.some(x=>x.event==='purchase')");const hostLayer=await run('return dataLayer');assert.deepEqual(hostLayer.find(x=>x.event==='purchase').user_data,{email:'visitor@example.test',phone_number:'+420601234567'});assert.equal(JSON.stringify(hostLayer).includes('private'),false);assert.equal(hostLayer.at(-1).user_data,null,'the contact is cleared after the conversion');
 await run("await call('capture');await call('observe');return true");if(cmp)await run("cmpChoose(false);return true");else await run('choice=null;notify();return true');await until(s=>s.consent?.marketing===false,'refusal is reported as state');assert.equal(state.state,'active','refusal keeps measuring');await run('dataLayer.length=0;return true');await run(`await call('confirm',${JSON.stringify({...purchase,user_data:undefined})});await call('resolve');return true`);await page.waitForFunction("dataLayer.some(x=>x.event==='purchase')");
 await run('disconnect();return true');await new Promise(r=>setTimeout(r,150));assert.equal((await run("return await call('state')")).state,'active','disconnecting a source keeps measuring');await run('dataLayer.length=0;return true');
 const envelope={namespace:'festapp-embed',protocol:1,type:'analytics',instance:state.instance,payload:{event:'page_view'}};
 await run(`window.dispatchEvent(new MessageEvent('message',{origin:'http://127.0.0.1:1',source:document.querySelector('iframe').contentWindow,data:${JSON.stringify(envelope)}}));window.dispatchEvent(new MessageEvent('message',{origin:${JSON.stringify(childOrigin)},source:window,data:${JSON.stringify(envelope)}}));await call('post',${JSON.stringify(envelope)});return true`);await new Promise(r=>setTimeout(r,150));assert.deepEqual(await run('return dataLayer'),[],'forged origin, source and protocol 1 messages are rejected');
 if (!cmp) {
  await run("window.staleNotify=null;window.staleDispose=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>({processingRevision:'rev-a',analytics:true,marketing:true}),subscribe:n=>{staleNotify=n;return ()=>{}}});return true");
  await until(s=>s.consent?.marketing===true,'source grant before replacement');
  await run("window.currentDispose=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>({processingRevision:'rev-a',analytics:true,marketing:false}),subscribe:()=>()=>{}});staleDispose();staleNotify();return true");
  await until(s=>s.consent?.analytics===true && s.consent?.marketing===false,'stale disposer and callback cannot replace current choice');
  await run("FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>{throw Error('read failed')},subscribe:()=>()=>{}});return true");
  await until(s=>s.consent?.analytics===false && s.state==='active','failed read denies choice while lease remains active');
  await run("FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),true);FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>({processingRevision:'rev-a',analytics:true,marketing:true}),subscribe:()=>{throw Error('subscribe failed')}});return true");
  await until(s=>s.consent?.analytics===false && s.state==='active','failed subscribe denies choice without resurrecting prior grant');
  await run("Object.defineProperty(document,'hidden',{configurable:true,value:true});document.dispatchEvent(new Event('visibilitychange'));dataLayer.length=0;await call('raw',{event:'form_start'});return true");
  await page.waitForFunction("dataLayer.some(x=>x.event==='form_start')");assert.equal((await run("return await call('state')")).state,'active','hidden tab keeps its lease');
  await run("delete document.hidden;document.dispatchEvent(new Event('visibilitychange'));return true");
  const instanceA=state.instance;
  await run(`window.originalFrame=document.querySelector('iframe');window.beforeReady=fixtureReadyCount;originalFrame.src=${JSON.stringify(childBOrigin+'/form/test?embed=1')};return true`);
  await page.waitForFunction('fixtureReadyCount>beforeReady');await until(s=>s.state==='active' && s.instance!==instanceA,'B origin receives a fresh active record');const instanceB=state.instance;
  assert.equal(await run('return heartbeats.size'),1,'only B heartbeat remains after replacement');
  await run(`window.beforeReady=fixtureReadyCount;originalFrame.src=${JSON.stringify(childOrigin+'/form/test?embed=1')};return true`);
  await page.waitForFunction('fixtureReadyCount>beforeReady');await until(s=>s.state==='active' && s.instance!==instanceA && s.instance!==instanceB,'return to A receives a fresh active record');
  assert.equal(await run('return document.querySelector("iframe")===originalFrame && heartbeats.size===1'),true,'same element has only its current heartbeat');
  await run("originalFrame.remove();return true");await page.waitForFunction('heartbeats.size===0');
  console.log('PASS: broken sources, stale callbacks, hidden tab, A/B/A record replacement and detach');
  await page.goto(origin);await page.waitForFunction('window.call && document.querySelector("iframe")');await until(s=>s.state==='active','fresh frame after lifecycle checks');
 }
 await run("await call('denyHost');return true");await until(s=>s.state!=='active','unapproved host stops');await run("dataLayer.length=0;await call('view');return true");await new Promise(r=>setTimeout(r,150));assert.deepEqual(await run('return dataLayer'),[],'unapproved host cannot activate');
 await page.goto(`${origin}/?private=1`);await until(s=>s.instance,'private layout initialized');await new Promise(r=>setTimeout(r,300));assert.notEqual((await run("return await call('state')")).state,'active','private entry remains ineligible');assert.deepEqual(await run('return dataLayer'),[]);
 console.log(`PASS: ${cmp?'Klaro':'host'} always-on measurement, consent state, forged messages, private entry, contact allowlist and pending operations`);
   }, {suite: 'form_measurement_browser', scenario: cmp ? 'cmp' : 'host'});
  } finally { await context?.close(); }
 }
} finally { try { await owner.close(); } finally { await Promise.all([host?.close(),child?.close(),childB?.close()]); } }
