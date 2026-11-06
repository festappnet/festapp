#!/usr/bin/env node
import assert from 'node:assert/strict';
import {createServer as httpServer} from 'node:http';
import {createServer} from 'vite';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,readFile,rm,mkdir} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {serveMeasurement} from '../../workers/form-measurement/src/worker.mjs';
import {openIsolatedBrowser} from './isolated_browser_startup.mjs';
const root=path.resolve(import.meta.dirname,'..'), exec=promisify(execFile), temp=await mkdtemp(path.join(tmpdir(),'fm-runtime-'));
const configPath=path.join(temp,'browser.json'); await writeFile(configPath,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false}));
const previewAuth=process.env.FORM_GTM_PREVIEW_AUTH_FILE ? (await readFile(process.env.FORM_GTM_PREVIEW_AUTH_FILE,'utf8')).trim() : null;
let host, server, session=`fmr-${process.pid}`, index=0;
const browser=async(...args)=>{const {stdout}=await exec('agent-browser',['--config',configPath,'--namespace',session,'--session',session,'--headed','false','--json',...args],{timeout:30000});const d=JSON.parse(stdout);assert.equal(d.success,true,d.error);return d.data;};
try {
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'host-fixture',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('content-type','text/html; charset=utf-8');res.end('<!doctype html><meta charset="utf-8"><title>Local runtime test</title><script type="module" src="/tests/fixtures/form_measurement/runtime_host.js"></script>');});}}]}); await host.listen();
 const parent=`http://127.0.0.1:${host.httpServer.address().port}`;
 server=httpServer(async(req,res)=>{const origin=`http://localhost:${server.address().port}`;const response=await serveMeasurement(new Request(origin+req.url),{LOCAL_TEST:true,ORGANIZATION_ID:1,UNIT_ID:2},async args=>({organization:1,unit:2,form_id:1,form_link:'test',runtime_origin:origin,parent_origin:parent,ancestor_origins:[parent],profile:'gtm-v1',collector_origins:[],policy:{eligible:true,runtime_supported:true},gtm_container:'GTM-W9WRHWT9',scripts:'<script>window.__festappConsentReceipt=function(value){parent.postMessage({fixtureConsent:value},'+JSON.stringify(parent)+')}; new MutationObserver(function(records){records.forEach(function(r){r.addedNodes.forEach(function(n){if(n.tagName===\"SCRIPT\") parent.postMessage({fixtureScript:{hasSrc:!!n.src,hasNonce:!!n.nonce,nonceMatches:n.nonce===document.querySelector(\"script[nonce]\").nonce}},'+JSON.stringify(parent)+');});});}).observe(document.documentElement,{childList:true,subtree:true}); window.addEventListener(\"securitypolicyviolation\",function(e){parent.postMessage({fixtureViolation:e.violatedDirective, blocked:e.blockedURI},'+JSON.stringify(parent)+')}); setTimeout(function(){parent.postMessage({fixtureGtm:!!window.google_tag_manager,fixtureCount:dataLayer.length},'+JSON.stringify(parent)+')},5000); var originalPush=dataLayer.push; dataLayer.push=function(){var out=originalPush.apply(this,arguments); parent.postMessage({fixtureMeasurement:Array.prototype.slice.call(arguments)}, '+JSON.stringify(parent)+'); return out;};</script>'}));res.writeHead(response.status,Object.fromEntries(response.headers)); let body=await response.text(); if(previewAuth && req.url==='/runtime.js') body=body.replace('config.gtm_container;', 'config.gtm_container + '+JSON.stringify('&gtm_auth='+previewAuth+'&gtm_preview='+encodeURIComponent(process.env.FORM_GTM_PREVIEW_ENV || '')+'&gtm_cookies_win=x')+';'); res.end(body);}); await new Promise(resolve=>server.listen(0,'::',resolve));
 const runtime=`http://localhost:${server.address().port}`, url=`${parent}/form/test?runtime=${encodeURIComponent(runtime)}&gclid=synthetic123&email=private%40example.com`;
 if(process.argv.includes('--serve')) {console.log(`READY ${url}`);await new Promise(resolve=>process.once('SIGTERM',resolve));}
 else {
 await openIsolatedBrowser({open:async()=>{session=`fmr-${process.pid}-${++index}`;await browser('open');},info:()=>browser('session','info'),close:()=>browser('close')});
 await browser('open',url); await browser('wait','--fn','!!window.runtime'); const run=async s=>(await browser('eval',s)).result;
 assert.equal(await run('document.querySelectorAll("iframe").length'),0);assert.equal(await run("window.event('page_view')"),false);
 await run('runtime.setConsent(true)'); await browser('wait','--fn','window.ready === true');
 assert.equal(await run('runtime.frame.getAttribute("sandbox")'),'allow-scripts allow-same-origin');
 assert.equal(await run('(()=>{try{return !!runtime.frame.contentWindow.document}catch(e){return false}})()'),false);
 for(const event of ['page_view','view_item','purchase'])assert.equal(await run(`window.event('${event}')`),true);
 if(previewAuth) { await browser('wait','--fn',"window.gtmReceipts?.length >= 3 || window.diagnostics?.some(x=>x.fixtureGtm !== undefined)"); const report=await run('({receipts:window.gtmReceipts,diagnostics:window.diagnostics})'); assert.equal(report.receipts.length,3,'GTM diagnostic tag receipts: '+JSON.stringify(report.diagnostics)); await browser('wait','--fn','consentReceipts.length >= 3'); assert.deepEqual(await run('consentReceipts[0]'),{analytics:true,ad_storage:false,ad_user_data:false,ad_personalization:false}); console.log('PASS: Google consent API analytics granted, advertising denied'); assert.deepEqual(report.receipts.map(x=>x.event),['page_view','view_item','purchase']); for(const receipt of report.receipts){assert.equal(receipt.page_location,`${parent}/form/test?gclid=synthetic123`);assert.equal(receipt.gclid,'synthetic123');} console.log('PASS: unpublished GTM preview diagnostic tag fired for three events'); }
 await browser('wait','--fn',"window.observed?.some(x=>x.event==='purchase')"); const layer=await run('window.observed');assert.ok(layer.some(x=>x.event==='purchase'));assert.equal(JSON.stringify(layer).includes('secret@example.com'),false);assert.equal(JSON.stringify(layer).includes('private@example.com'),false); const page=layer.find(x=>x.event==='page_view'); assert.equal(page.page_location,`${parent}/form/test?gclid=synthetic123`);assert.equal(page.gclid,'synthetic123');
 await run('runtime.setConsent(false)');assert.equal(await run('document.querySelectorAll("iframe").length'),0);assert.equal(await run("window.event('page_view')"),false); await run('model.data.analytics.eligible=false;runtime.setConsent(true)');assert.equal(await run('document.querySelectorAll("iframe").length'),0);
 console.log('PASS: isolated runtime consent gate, cross-origin sandbox, event projection, PII stripping, revoke and policy denial');
 await mkdir(path.join(root,'node_modules/.cache'),{recursive:true});
 for (const lang of ['cs','en']) {
  await run("document.cookie='festapp-measurement-1-2=; Max-Age=0; path=/'");
  await browser('open',url+'&cmp=1&lang='+lang);
  await browser('wait','--fn','!!document.querySelector(".cookie-modal-notice")');
  const notice=await run(`(()=>{
   const node=document.querySelector('.cookie-modal-notice');
   return {text:node.innerText,buttons:[...node.querySelectorAll('button')].map(b=>b.innerText),
    inputs:node.querySelectorAll('input').length,close:node.querySelectorAll('.hide').length,
    overflow:document.body.style.overflow};
  })()`);
  console.log(JSON.stringify({lang,...notice}));
  assert(!/<tr-|počítače/.test(notice.text));
  assert.deepEqual(notice.buttons,lang==='cs'?['Odmítnout','Přijmout']:['Decline','Accept']);
  assert.equal(notice.inputs,0);assert.equal(notice.close,0);assert.equal(notice.overflow,'hidden');
  await browser('screenshot',path.join(root,`node_modules/.cache/lista-${lang}.png`));
  await run('cleanupCmp()');assert.equal(await run('document.body.style.overflow'),'');
 }
 for (const privacy of ['https://organizer.example/privacy', '', 'javascript:alert(1)', 'https://user:pass@example.com']) {
  await run("document.cookie='festapp-measurement-1-2=; Max-Age=0; path=/'");
  await browser('open',url+'&cmp=1&privacy='+encodeURIComponent(privacy));
  await browser('wait','--fn','!!window.cleanupCmp');
  if (privacy==='https://organizer.example/privacy') {
   assert.equal(await run('document.querySelector(".cookie-modal-notice a").getAttribute("href")'),privacy);
  } else {
   assert.equal(await run('document.querySelector("#festapp-measurement-consent, .btn-text, iframe")'),null);
   assert.equal(await run('document.body.style.overflow'),'');
   assert.equal(await run('runtime.measurementAllowed()'),false);
  }
  await run('cleanupCmp()');
 }
 console.log('PASS: consent privacy URL uses organizer HTTPS link and rejects unsafe links');
 await browser('open',url+'&cmp=1'); await browser('wait','--fn','!!window.cleanupCmp && !!document.querySelector(".cookie-modal-notice")'); assert.equal(await run('document.querySelectorAll("iframe").length'),0); await run('document.querySelector(".cookie-modal-notice .cm-btn-success").click()'); await browser('wait','--fn','window.ready === true'); assert.equal(await run('runtime.measurementAllowed()'),true); await browser('reload'); await browser('wait','--fn','!!window.cleanupCmp && runtime.measurementAllowed()'); assert.equal(await run('!!document.querySelector(".cookie-modal, .cookie-notice")'),false,'saved choice restores without opening consent UI'); await run('document.querySelector(".btn-text").click()'); await browser('wait','--fn','!!document.querySelector(".cm-list-input")'); await run('document.querySelector(".cm-list-input").click();document.querySelector(".cm-btn-accept").click()'); await browser('wait','--fn','!runtime.frame'); assert.equal(await run('runtime.measurementAllowed()'),false); console.log('PASS: actual Klaro UI grant, quiet saved-choice restore, reopened preferences and revoke');
 }
} finally {if(!process.argv.includes('--serve'))try{await browser('close')}catch{} if(host)await host.close();if(server)await new Promise(resolve=>server.close(resolve));await rm(temp,{recursive:true,force:true});}
