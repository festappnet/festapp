#!/usr/bin/env node
import {timed} from './test_timings.mjs';
import assert from 'node:assert/strict';
import {createServer as httpServer} from 'node:http';
import {createServer} from 'vite';
import path from 'node:path';
import {serveMeasurement} from '../../workers/form-measurement/src/worker.mjs';
import {createNativeBrowser} from './native_browser.mjs';
const root=path.resolve(import.meta.dirname,'..');
let host,server,parent,origin,tagRequests=0;
const owner=await createNativeBrowser(); let context,page;
try {
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'host',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('content-type','text/html');res.end('<!doctype html><html lang="en"><script type="module" src="/tests/fixtures/form_measurement/runtime_host.js"></script></html>')})}}]});await timed('browser.server-start', () => host.listen(), {suite: 'form_measurement_runtime_browser'});parent=`http://127.0.0.1:${host.httpServer.address().port}`;
 server=httpServer(async(req,res)=>{if(req.url==='/tag.js'){tagRequests++;res.setHeader('content-type','application/javascript');res.end(`const identity=()=>({cookies:document.cookie,url:location.href,clientIds:dataLayer.filter(x=>x[0]==='set'&&x[1]?.client_id).map(x=>x[1].client_id)});parent.postMessage({fixtureIdentity:identity()},${JSON.stringify(parent)});parent.postMessage({fixtureTag:true},${JSON.stringify(parent)});var old=dataLayer.push;dataLayer.push=function(){var r=old.apply(this,arguments);parent.postMessage({fixtureIdentity:identity()},${JSON.stringify(parent)});parent.postMessage({fixtureMeasurement:Array.from(arguments).filter(x=>Object.prototype.toString.call(x)!=='[object Arguments]')},${JSON.stringify(parent)});return r}`);return;}const response=await serveMeasurement(new Request(origin+req.url),{LOCAL_TEST:true,ORGANIZATION_ID:1,UNIT_ID:2},async()=>({organization:1,unit:2,form_id:1,form_link:'test',runtime_origin:origin,parent_origin:parent,ancestor_origins:[parent],profile:'gtm-v1',collector_origins:[],policy:{eligible:true,runtime_supported:true,organization:1,unit:2,processing_revision:'rev-a',measurement_protocol:3,runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']},gtm_container:null,scripts:`<script src="${origin}/tag.js"></script>`}));res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));});await new Promise(r=>server.listen(0,'::',r));origin=`http://localhost:${server.address().port}`;
 owner.allow(parent);owner.allow(origin);context=await owner.context();page=await context.newPage();await owner.setTopLevelColorScheme(page,'light');await page.goto(`${parent}/form/test?runtime=${encodeURIComponent(origin)}&gclid=synthetic123&email=private%40example.com`);await page.waitForFunction('!!window.runtime');const run=s=>page.evaluate(`(()=>{return (${s})})()`);
 assert.equal(await run('document.querySelectorAll("iframe").length'),0);assert.equal(tagRequests,0);assert.equal(await run("event('page_view')"),false);
 await run("(setTimeout(()=>runtime.activate(grant('rev-b')),0),true)");await new Promise(r=>setTimeout(r,1500));const mismatchState=await run('({mismatch:window.mismatch,executed})');assert.equal(mismatchState.mismatch,true);assert.equal(tagRequests,0);assert.equal(mismatchState.executed,0,'mismatched Worker never executes Unit code');
 await run('(setTimeout(()=>runtime.activate({...grant(),consent:{analytics:false,marketing:false}}),0),true)');await page.waitForFunction('window.ready && window.executed===1');assert.equal(tagRequests,1,'a refused choice still loads the tag');const frameState=await run('({sandbox:runtime.frame.getAttribute("sandbox"),accessible:(()=>{try{return !!runtime.frame.contentWindow.document}catch{return false}})()})');assert.equal(frameState.sandbox,'allow-scripts allow-same-origin');assert.equal(frameState.accessible,false);
 for (const choice of [{analytics:true,marketing:false},{analytics:false,marketing:false}]) {
  const before=await run("observed.filter(x=>x.event==='festapp_consent_update').length");
  await run(`(runtime.updateConsent(${JSON.stringify(choice)}),true)`);
  await page.waitForFunction(`observed.filter(x=>x.event==='festapp_consent_update').length>${before}`);
  const update=await run("observed.filter(x=>x.event==='festapp_consent_update').at(-1)");
  assert.deepEqual(update.festapp_consent,choice,'the update itself carries the new nested snapshot before a conversion');
  assert.equal(update.analytics,choice.analytics);assert.equal(update.marketing,choice.marketing);
 }
 assert.equal(await run("event('page_view')"),true);assert.equal(await run("event('purchase')"),true);await page.waitForFunction("observed.some(x=>x.event==='purchase')");const events=await run('observed');assert.equal(JSON.stringify(events).includes('secret@example.com'),false);assert.deepEqual(events.find(x=>x.event==='purchase').user_data,{email:'buyer@example.com',phone_number:'+420601234567'});assert.equal(events.find(x=>x.event==='page_view').gclid,'synthetic123');
 await run('(runtime.stop(),true)');assert.equal(await run("event('page_view')"),false);assert.equal(await run('document.querySelectorAll("iframe").length'),0);console.log('PASS: refused consent still runs real tag request and execution; mismatch, contact allowlist, sandbox and stop');
 // Real cross-origin runtime: the local HTTP fixture may block Secure cookies,
 // in which case the deterministic GA fallback must still be visible to GTM.
 await page.goto(`${parent}/form/test?runtime=${encodeURIComponent(origin)}&identity=1&_gl=1*embed&gtm_debug=x`);
 await page.waitForFunction('!!window.runtime');
 await context.addCookies([{name:'_ga',value:'GA1.1.999.999',domain:'localhost',path:'/',secure:true,sameSite:'None'},{name:'_ga_OLD',value:'GS2.1.s999$o9',domain:'localhost',path:'/',secure:true,sameSite:'None'}]);
 assert((await context.cookies(origin)).some(c=>c.name==='_ga'&&c.value==='GA1.1.999.999'));
 await run("(runtime.activate({...grant(),hostIdentity:{_ga:'GA1.1.123.456',_gcl_aw:'GCL.123.identity-click',_fbp:'fb.1.123.456'}}),true)");
 await page.waitForFunction('!!window.runtimeIdentity && window.ready');
 const identity=await run('runtimeIdentity');
 assert(identity.cookies.includes('_ga=GA1.1.123.456') || identity.clientIds.includes('123.456'));
 const gaValues=identity.cookies.split(';').map(x=>x.trim()).filter(x=>x.startsWith('_ga='));
 assert(gaValues.length===0 || gaValues.length===1&&gaValues[0]==='_ga=GA1.1.123.456');
 assert.doesNotMatch(identity.cookies,/_ga_OLD=|GA1\.1\.999\.999/);
 assert.equal(new URL(identity.url).searchParams.has('gclid'),false);
 assert.equal(new URL(identity.url).searchParams.has('_gl'),false);
 assert.equal(new URL(identity.url).searchParams.has('gtm_debug'),false);
 await run('(runtime.updateConsent({analytics:false,marketing:false}),true)');
 await page.waitForFunction("observed.some(x=>x.event==='festapp_consent_update')");
 assert.doesNotMatch(await run('runtimeIdentity.cookies'),/_ga=|_gcl_aw=|_fbp=/);
 await page.goto(`${parent}/form/test?runtime=${encodeURIComponent(origin)}&_gl=1*direct._-1&gtm_debug=x`);
 await page.waitForFunction('!!window.runtime');await run('(runtime.activate(grant()),true)');
 await page.waitForFunction('!!window.runtimeIdentity && window.ready');
 const direct=await run('runtimeIdentity');assert.equal(new URL(direct.url).searchParams.get('_gl'),'1*direct._-1');
 assert.equal(new URL(direct.url).searchParams.get('gtm_debug'),'x');
 assert.doesNotMatch(await run('JSON.stringify(observed)'),/_gl|gtm_debug/);
 console.log('PASS: embedded host identity, cookie fallback/revocation and direct-only linker URL');
 for(const lang of ['cs','en']) {
  await page.goto(`${parent}/form/test?runtime=${encodeURIComponent(origin)}&cmp=1&lang=${lang}`);await page.waitForFunction('!!document.querySelector(".cookie-modal-notice")');
  const notice=await run(`({buttons:[...document.querySelectorAll('.cookie-modal-notice button')].map(x=>x.innerText),href:document.querySelector('.cookie-modal-notice a').getAttribute('href'),frames:document.querySelectorAll('iframe').length})`);
  assert.deepEqual(notice.buttons,lang==='cs'?['Odmítnout','Přijmout','Nastavení']:['Decline','Accept','Settings']);assert.equal(notice.href,'https://organizer.example/privacy');assert.equal(notice.frames,0);await run('(cleanupCmp(),true)');
 }
 for(const privacy of ['', 'javascript:alert(1)', 'https://user:pass@example.com']) {
  await page.goto(`${parent}/form/test?runtime=${encodeURIComponent(origin)}&cmp=1&privacy=${encodeURIComponent(privacy)}`);await page.waitForFunction('!!window.cleanupCmp');assert.equal(await run('document.querySelector("#festapp-measurement-consent, .btn-text, iframe")'),null);
 }
 console.log('PASS: localized consent notices and safe organizer privacy links');
} finally {try { await owner.close(); } finally { await Promise.all([host?.close(),server && new Promise((resolve,reject)=>server.close(error=>error?reject(error):resolve()))]); }}
