#!/usr/bin/env node
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,writeFile,readFile,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {createServer} from 'vite';
import {openIsolatedBrowser} from './isolated_browser_startup.mjs';
const cmp = process.argv.includes('--cmp');
const liveGtm = process.argv.includes('--live-gtm');
const execute=promisify(execFile), root=path.resolve(import.meta.dirname,'..');
const temp=await mkdtemp(path.join(tmpdir(),'form-measurement-'));
const config=path.join(temp,'browser.json');
await writeFile(config,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false,args:'--mute-audio'}));
let session=`fm-${process.pid}`, index=0, host, child, childB;
async function browser(...args) {
 const {stdout}=await execute('agent-browser',['--config',config,'--namespace',session,'--session',session,'--headed','false','--allowed-domains',liveGtm?'127.0.0.1,www.googletagmanager.com':'127.0.0.1','--json',...args],{timeout:30000,env:{...process.env,AGENT_BROWSER_CONFIG:config,AGENT_BROWSER_PLUGINS:'[]'}});
 const data=JSON.parse(stdout); assert.equal(data.success,true,data.error); return data.data;
}
try {
 child=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-child',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><script type="module" src="/tests/fixtures/form_measurement/child.js"></script></body></html>')})}}]});
 await child.listen(); const childOrigin=`http://127.0.0.1:${child.httpServer.address().port}`;
 childB=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-child-b',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><script type="module" src="/tests/fixtures/form_measurement/child.js"></script></body></html>')})}}]});
 await childB.listen();const childBOrigin=`http://127.0.0.1:${childB.httpServer.address().port}`;
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-host',configureServer(s){s.middlewares.use((req,res,next)=>{if(req.url==='/cmp/klaro.js'){res.setHeader('Content-Type','application/javascript; charset=utf-8');readFile(path.join(root,'node_modules/klaro/dist/klaro.js')).then(value=>res.end(value));return}if(req.url==='/away'){res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><title>Away</title>');return}if(!['/','/?private=1'].includes(req.url) && !(cmp && req.url.startsWith('/?cmp=1')))return next();const privateEntry=req.url.includes('private=1');res.setHeader('Content-Type','text/html; charset=utf-8');res.end(`<!doctype html><html><head><meta charset="utf-8"></head><body><iframe data-festapp-embed data-festapp-datalayer src="${childOrigin}/form/test?embed=1${privateEntry?'&token=private#secret':''}"></iframe><script>window.addEventListener('pageshow',e=>sessionStorage.setItem('fixture-pageshow',JSON.stringify({persisted:e.persisted,navigation:performance.getEntriesByType('navigation')[0]?.type})));window.heartbeats=new Set();const fixtureSetInterval=window.setInterval,fixtureClearInterval=window.clearInterval;window.setInterval=(fn,ms,...args)=>{const id=fixtureSetInterval(fn,ms,...args);if(ms===20000)heartbeats.add(id);return id};window.clearInterval=id=>{heartbeats.delete(id);return fixtureClearInterval(id)};window.fixtureReadyCount=0;window.dataLayer=[];window.replies=new Map();window.addEventListener('message',e=>{if(e.data?.fixtureReady)fixtureReadyCount++;if(e.data?.fixtureReply){const f=window.replies.get(e.data.id);if(f){window.replies.delete(e.data.id);f(e.data)}}});window.call=(action,arg)=>new Promise((resolve,reject)=>{const id=crypto.randomUUID();window.replies.set(id,r=>r.error?reject(Error(r.error)):resolve(r.result));document.querySelector('iframe').contentWindow.postMessage({fixture:true,id,action,arg},'*');setTimeout(()=>reject(Error('fixture timeout '+action)),5000)});</script><script src="/embed.js"></script>${cmp?'<script>window.fixtureErrors=[];window.addEventListener("error",e=>fixtureErrors.push({message:e.message,source:e.filename,line:e.lineno,target:e.target?.src}),true)</script><script src="/cmp/klaro.js" onload="window.klaroLoaded=true" onerror="window.klaroLoaded=false"></script><script src="/tests/fixtures/form_measurement/klaro_host.js"></script>':''}</body></html>`)})}}]});
 await host.listen(); const origin=`http://127.0.0.1:${host.httpServer.address().port}`;
 await openIsolatedBrowser({open:async()=>{session=`fm-${process.pid}-${++index}`;await browser('open')},info:()=>browser('session','info'),close:()=>browser('close')});
 await browser('open',cmp?`${origin}/?cmp=1${liveGtm?'&live-gtm=1':''}`:origin); await browser('wait','--fn','!!window.FestappEmbed && !!document.querySelector("iframe")');
 const run=async code=>{const d=await browser('eval',`(async()=>{${code}})()`);return d.result};
 await browser('wait','--fn','window.call && document.querySelector("iframe")');
 let state;const until=async(test,label)=>{for(let i=0;i<120;i++){state=await run("return await call('state')");if(state&&test(state))return;await new Promise(r=>setTimeout(r,50))}assert.fail(label+': '+JSON.stringify(state))};
 await until(s=>s.instance,'layout bridge initialized');await until(s=>s.state==='active','a helper alone activates without any consent source');
 await run("await call('view');return true");await browser('wait','--fn',"dataLayer.some(x=>x.event==='page_view')");
 await run("FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),true);return true");await new Promise(r=>setTimeout(r,150));assert.equal((await run("return await call('state')")).state,'active','a choice never stops measurement');
 if(cmp){await browser('wait','--fn','!!window.cmpManager || !!window.cmpFailure');assert.equal(await run('return cmpFailure'),null);await run("window.disconnect=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),cmpSource);return true");await run("cmpChoose(true,false);return true");await until(s=>s.consent?.analytics===true && s.consent?.marketing===false,'one purpose is reported as state');await run("cmpChoose(true,true);return true");await until(s=>s.consent?.marketing===true,'both purposes are reported as state');}
 else {await run("window.choice=null;window.notify=null;window.disconnect=FestappEmbed.connectMeasurementConsent(document.querySelector('iframe'),{read:()=>choice,subscribe:n=>{notify=n;return ()=>notify=null}});return true");await run("choice={processingRevision:'rev-a',analytics:true,marketing:true};notify();return true");await until(s=>s.consent?.marketing===true,'a source reports the saved choice');}
 assert.equal(state.state,'active');await run('dataLayer.length=0;return true');
 const purchase={event:'purchase',email:'private@example.test',user_data:{email:'visitor@example.test',phone_number:'+420601234567',first_name:'private'},ecommerce:{currency:'CZK',transaction_id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',payment_type:'card',items:[{item_id:'product_1',item_name:'Ticket',price:10,quantity:1,email:'private@example.test'}]}};
 await run(`await call('raw',${JSON.stringify(purchase)});return true`);await browser('wait','--fn',"dataLayer.some(x=>x.event==='purchase')");const hostLayer=await run('return dataLayer');assert.deepEqual(hostLayer.find(x=>x.event==='purchase').user_data,{email:'visitor@example.test',phone_number:'+420601234567'});assert.equal(JSON.stringify(hostLayer).includes('private'),false);assert.equal(hostLayer.at(-1).user_data,null,'the contact is cleared after the conversion');
 await run("await call('capture');await call('observe');return true");if(cmp)await run("cmpChoose(false);return true");else await run('choice=null;notify();return true');await until(s=>s.consent?.marketing===false,'refusal is reported as state');assert.equal(state.state,'active','refusal keeps measuring');await run('dataLayer.length=0;return true');await run(`await call('confirm',${JSON.stringify({...purchase,user_data:undefined})});await call('resolve');return true`);await browser('wait','--fn',"dataLayer.some(x=>x.event==='purchase')");
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
  await browser('wait','--fn',"dataLayer.some(x=>x.event==='form_start')");assert.equal((await run("return await call('state')")).state,'active','hidden tab keeps its lease');
  await run("delete document.hidden;document.dispatchEvent(new Event('visibilitychange'));return true");
  const instanceA=state.instance;
  await run(`window.originalFrame=document.querySelector('iframe');window.beforeReady=fixtureReadyCount;originalFrame.src=${JSON.stringify(childBOrigin+'/form/test?embed=1')};return true`);
  await browser('wait','--fn','fixtureReadyCount>beforeReady');await until(s=>s.state==='active' && s.instance!==instanceA,'B origin receives a fresh active record');const instanceB=state.instance;
  assert.equal(await run('return heartbeats.size'),1,'only B heartbeat remains after replacement');
  await run(`window.beforeReady=fixtureReadyCount;originalFrame.src=${JSON.stringify(childOrigin+'/form/test?embed=1')};return true`);
  await browser('wait','--fn','fixtureReadyCount>beforeReady');await until(s=>s.state==='active' && s.instance!==instanceA && s.instance!==instanceB,'return to A receives a fresh active record');
  assert.equal(await run('return document.querySelector("iframe")===originalFrame && heartbeats.size===1'),true,'same element has only its current heartbeat');
  await run("originalFrame.remove();return true");await browser('wait','--fn','heartbeats.size===0');
  console.log('PASS: broken sources, stale callbacks, hidden tab, A/B/A record replacement and detach');
  await browser('open',origin);await browser('wait','--fn','window.call && document.querySelector("iframe")');await until(s=>s.state==='active','fresh frame after lifecycle checks');
 }
 await run("await call('denyHost');return true");await until(s=>s.state!=='active','unapproved host stops');await run("dataLayer.length=0;await call('view');return true");await new Promise(r=>setTimeout(r,150));assert.deepEqual(await run('return dataLayer'),[],'unapproved host cannot activate');
 await browser('open',`${origin}/?private=1`);await until(s=>s.instance,'private layout initialized');await new Promise(r=>setTimeout(r,300));assert.notEqual((await run("return await call('state')")).state,'active','private entry remains ineligible');assert.deepEqual(await run('return dataLayer'),[]);
 console.log(`PASS: ${cmp?'Klaro':'host'} always-on measurement, consent state, forged messages, private entry, contact allowlist and pending operations`);

} finally { try{await browser('close')}catch{} await Promise.allSettled([host?.close(),child?.close(),childB?.close()]); await rm(temp,{recursive:true,force:true}); }
