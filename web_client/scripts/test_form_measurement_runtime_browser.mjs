#!/usr/bin/env node
import assert from 'node:assert/strict';
import {createServer as httpServer} from 'node:http';
import {createServer} from 'vite';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {serveMeasurement} from '../../workers/form-measurement/src/worker.mjs';
import {openIsolatedBrowser} from './isolated_browser_startup.mjs';
const root=path.resolve(import.meta.dirname,'..'),exec=promisify(execFile),tmp=await mkdtemp(path.join(tmpdir(),'fmr-')),cfg=path.join(tmp,'config.json');
await writeFile(cfg,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false,args:'--mute-audio'}));
let host,server,session=`fmr-${process.pid}`,index=0,parent,origin,tagRequests=0;
const browser=async(...args)=>{const {stdout}=await exec('agent-browser',['--config',cfg,'--namespace',session,'--session',session,'--headed','false','--json',...args],{timeout:30000});const d=JSON.parse(stdout);assert.equal(d.success,true,d.error);return d.data};
try {
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'host',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('content-type','text/html');res.end('<!doctype html><html lang="en"><script type="module" src="/tests/fixtures/form_measurement/runtime_host.js"></script></html>')})}}]});await host.listen();parent=`http://127.0.0.1:${host.httpServer.address().port}`;
 server=httpServer(async(req,res)=>{if(req.url==='/tag.js'){tagRequests++;res.setHeader('content-type','application/javascript');res.end(`parent.postMessage({fixtureTag:true},${JSON.stringify(parent)});var old=dataLayer.push;dataLayer.push=function(){var r=old.apply(this,arguments);parent.postMessage({fixtureMeasurement:Array.from(arguments).filter(x=>Object.prototype.toString.call(x)!=='[object Arguments]')},${JSON.stringify(parent)});return r}`);return;}const response=await serveMeasurement(new Request(origin+req.url),{LOCAL_TEST:true,ORGANIZATION_ID:1,UNIT_ID:2},async()=>({organization:1,unit:2,form_id:1,form_link:'test',runtime_origin:origin,parent_origin:parent,ancestor_origins:[parent],profile:'gtm-v1',collector_origins:[],policy:{eligible:true,runtime_supported:true,organization:1,unit:2,processing_revision:'rev-a',measurement_protocol:3,runtime_revision:1,policy_revision:1,profile:'gtm-v1',required_purposes:['analytics','marketing']},gtm_container:null,scripts:`<script src="${origin}/tag.js"></script>`}));res.writeHead(response.status,Object.fromEntries(response.headers));res.end(Buffer.from(await response.arrayBuffer()));});await new Promise(r=>server.listen(0,'::',r));origin=`http://localhost:${server.address().port}`;
 await openIsolatedBrowser({open:async()=>{session=`fmr-${process.pid}-${++index}`;await browser('open')},info:()=>browser('session','info'),close:()=>browser('close')});await browser('open',`${parent}/form/test?runtime=${encodeURIComponent(origin)}&gclid=synthetic123&email=private%40example.com`);await browser('wait','--fn','!!window.runtime');const run=async s=>(await browser('eval',`(()=>{return (${s})})()`)).result;
 assert.equal(await run('document.querySelectorAll("iframe").length'),0);assert.equal(tagRequests,0);assert.equal(await run("event('page_view')"),false);
 await run("(setTimeout(()=>runtime.activate(grant('rev-b')),0),true)");await new Promise(r=>setTimeout(r,1500));assert.equal(await run('window.mismatch'),true);assert.equal(tagRequests,0);assert.equal(await run('executed'),0,'mismatched Worker never executes Unit code');
 await run('(setTimeout(()=>runtime.activate({...grant(),consent:{analytics:false,marketing:false}}),0),true)');await browser('wait','--fn','window.ready && window.executed===1');assert.equal(tagRequests,1,'a refused choice still loads the tag');assert.equal(await run('runtime.frame.getAttribute("sandbox")'),'allow-scripts allow-same-origin');assert.equal(await run('(()=>{try{return !!runtime.frame.contentWindow.document}catch{return false}})()'),false);
 for (const choice of [{analytics:true,marketing:false},{analytics:false,marketing:false}]) {
  const before=await run("observed.filter(x=>x.event==='festapp_consent_update').length");
  await run(`(runtime.updateConsent(${JSON.stringify(choice)}),true)`);
  await browser('wait','--fn',`observed.filter(x=>x.event==='festapp_consent_update').length>${before}`);
  const update=await run("observed.filter(x=>x.event==='festapp_consent_update').at(-1)");
  assert.deepEqual(update.festapp_consent,choice,'the update itself carries the new nested snapshot before a conversion');
  assert.equal(update.analytics,choice.analytics);assert.equal(update.marketing,choice.marketing);
 }
 assert.equal(await run("event('page_view')"),true);assert.equal(await run("event('purchase')"),true);await browser('wait','--fn',"observed.some(x=>x.event==='purchase')");const events=await run('observed');assert.equal(JSON.stringify(events).includes('secret@example.com'),false);assert.deepEqual(events.find(x=>x.event==='purchase').user_data,{email:'buyer@example.com',phone_number:'+420601234567'});assert.equal(events.find(x=>x.event==='page_view').gclid,'synthetic123');
 await run('(runtime.stop(),true)');assert.equal(await run("event('page_view')"),false);assert.equal(await run('document.querySelectorAll("iframe").length'),0);console.log('PASS: refused consent still runs real tag request and execution; mismatch, contact allowlist, sandbox and stop');
 for(const lang of ['cs','en']) {
  await browser('open',`${parent}/form/test?runtime=${encodeURIComponent(origin)}&cmp=1&lang=${lang}`);await browser('wait','--fn','!!document.querySelector(".cookie-modal-notice")');
  const notice=await run(`({buttons:[...document.querySelectorAll('.cookie-modal-notice button')].map(x=>x.innerText),href:document.querySelector('.cookie-modal-notice a').getAttribute('href'),frames:document.querySelectorAll('iframe').length})`);
  assert.deepEqual(notice.buttons,lang==='cs'?['Odmítnout','Přijmout']:['Decline','Accept']);assert.equal(notice.href,'https://organizer.example/privacy');assert.equal(notice.frames,0);await run('(cleanupCmp(),true)');
 }
 for(const privacy of ['', 'javascript:alert(1)', 'https://user:pass@example.com']) {
  await browser('open',`${parent}/form/test?runtime=${encodeURIComponent(origin)}&cmp=1&privacy=${encodeURIComponent(privacy)}`);await browser('wait','--fn','!!window.cleanupCmp');assert.equal(await run('document.querySelector("#festapp-measurement-consent, .btn-text, iframe")'),null);
 }
 console.log('PASS: localized consent notices and safe organizer privacy links');
} finally {try{await browser('close')}catch{}if(host)await host.close();if(server)await new Promise(r=>server.close(r));await rm(tmp,{recursive:true,force:true})}
