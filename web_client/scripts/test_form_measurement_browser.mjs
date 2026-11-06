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
await writeFile(config,JSON.stringify({provider:null,plugins:[],headed:false,autoConnect:false}));
let session=`fm-${process.pid}`, index=0, host, child;
async function browser(...args) {
 const {stdout}=await execute('agent-browser',['--config',config,'--namespace',session,'--session',session,'--headed','false','--allowed-domains',liveGtm?'127.0.0.1,www.googletagmanager.com':'127.0.0.1','--json',...args],{timeout:30000,env:{...process.env,AGENT_BROWSER_CONFIG:config,AGENT_BROWSER_PLUGINS:'[]'}});
 const data=JSON.parse(stdout); assert.equal(data.success,true,data.error); return data.data;
}
try {
 child=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-child',configureServer(s){s.middlewares.use((req,res,next)=>{if(!req.url.startsWith('/form/test'))return next();res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><html lang="en"><body><script type="module" src="/tests/fixtures/form_measurement/child.js"></script></body></html>')})}}]});
 await child.listen(); const childOrigin=`http://127.0.0.1:${child.httpServer.address().port}`;
 host=await createServer({root,configFile:false,logLevel:'error',server:{host:'127.0.0.1',port:0},plugins:[{name:'fixture-host',configureServer(s){s.middlewares.use((req,res,next)=>{if(req.url==='/cmp/klaro.js'){res.setHeader('Content-Type','application/javascript; charset=utf-8');readFile(path.join(root,'node_modules/klaro/dist/klaro.js')).then(value=>res.end(value));return}if(req.url==='/away'){res.setHeader('Content-Type','text/html; charset=utf-8');res.end('<!doctype html><title>Away</title>');return}if(!['/','/?private=1'].includes(req.url) && !(cmp && req.url.startsWith('/?cmp=1')))return next();const privateEntry=req.url.includes('private=1');res.setHeader('Content-Type','text/html; charset=utf-8');res.end(`<!doctype html><html><head><meta charset="utf-8"></head><body><iframe data-festapp-embed data-festapp-datalayer src="${childOrigin}/form/test?embed=1${privateEntry?'&token=private#secret':''}"></iframe><script>window.addEventListener('pageshow',e=>sessionStorage.setItem('fixture-pageshow',JSON.stringify({persisted:e.persisted,navigation:performance.getEntriesByType('navigation')[0]?.type})));window.dataLayer=[];window.replies=new Map();window.addEventListener('message',e=>{if(e.data?.fixtureReply){const f=window.replies.get(e.data.id);if(f){window.replies.delete(e.data.id);f(e.data)}}});window.call=(action,arg)=>new Promise((resolve,reject)=>{const id=crypto.randomUUID();window.replies.set(id,r=>r.error?reject(Error(r.error)):resolve(r.result));document.querySelector('iframe').contentWindow.postMessage({fixture:true,id,action,arg},'*');setTimeout(()=>reject(Error('fixture timeout '+action)),5000)});</script><script src="/embed.js"></script>${cmp?'<script>window.fixtureErrors=[];window.addEventListener("error",e=>fixtureErrors.push({message:e.message,source:e.filename,line:e.lineno,target:e.target?.src}),true)</script><script src="/cmp/klaro.js" onload="window.klaroLoaded=true" onerror="window.klaroLoaded=false"></script><script src="/tests/fixtures/form_measurement/klaro_host.js"></script>':''}</body></html>`)})}}]});
 await host.listen(); const origin=`http://127.0.0.1:${host.httpServer.address().port}`;
 await openIsolatedBrowser({open:async()=>{session=`fm-${process.pid}-${++index}`;await browser('open')},info:()=>browser('session','info'),close:()=>browser('close')});
 await browser('open',cmp?`${origin}/?cmp=1${liveGtm?'&live-gtm=1':''}`:origin); await browser('wait','--fn','!!window.FestappEmbed && !!document.querySelector("iframe")');
 const run=async code=>{const d=await browser('eval',`(async()=>{${code}})()`);return d.result};
 await browser('wait','--fn','window.call && document.querySelector("iframe")');
 let state; for(let i=0;i<20;i++){try{state=await run("return await window.call('state')");if(state?.instance)break}catch{} await new Promise(r=>setTimeout(r,100))} assert.ok(state?.instance,'bridge initialized');
 if (cmp) {
  await browser('wait','--fn','!!window.cmpManager || !!window.cmpFailure'); assert.equal(await run('return window.cmpFailure'),null,JSON.stringify(await run("const r=await fetch('/cmp/klaro.js');const t=await r.text();return {errors:window.fixtureErrors,loaded:window.klaroLoaded,status:r.status,type:r.headers.get('content-type'),length:t.length,start:t.slice(0,300)}")));
  const settle=()=>new Promise(r=>setTimeout(r,150));
  const count=()=>run("return dataLayer.filter(x=>x.event==='view_item').length");
  const consent=async(test,label)=>{for(let i=0;i<100;i++){const value=(await run("return await call('state')")).consent;if(value&&test(value))return;await new Promise(r=>setTimeout(r,20))}assert.fail(label)};
  await run("await call('view'); return true"); await settle();
  assert.equal(await count(),1,'events reach the host before any choice');
  assert.equal(await run('return cmpGtmState'),'not-requested','the host decides about its own container');
  await run("cmpChoose(false); return true");await consent(c=>c.analytics===false,'refusal reported');assert.equal((await run("return await call('state')")).allowed,true,'refusal stops nothing');
  await run("cmpManager.updateConsent('analytics',true);return true");await settle();
  await consent(c=>c.analytics===false,'unsaved draft selection is not reported');
  await run("cmpChoose(true);return true");await consent(c=>c.analytics===true,'saved CMP grant reaches embed');
  if(liveGtm){
   await browser('wait','--fn',"cmpGtmState==='loaded'||cmpGtmState==='blocked'");
   assert.equal(await run('return cmpGtmState'),'loaded','actual Google container fetched');
   assert.equal(await run("return !!window.google_tag_manager?.['GTM-W9WRHWT9']"),true,'real GTM container initialized');
   console.log('PASS: live empty GTM-W9WRHWT9 bootstrap initialized; tag firing remains unverified');
  }
  await run("cmpChoose(false);return true");await consent(c=>c.analytics===false,'revocation reported');
  assert.equal((await run("return await call('state')")).allowed,true,'revocation stops nothing');
  const commands=await run("return dataLayer.filter(x=>x[0]==='consent').map(x=>[x[1],x[2]])");
  assert.equal(commands[0][0],'default');assert.equal(commands[0][1].analytics_storage,'denied');
  assert.equal(commands.at(-1)[1].analytics_storage,'denied');
  assert.ok(commands.every(x=>x[1].ad_storage==='denied'&&x[1].ad_user_data==='denied'&&x[1].ad_personalization==='denied'));
  assert.ok(!(await run('return document.cookie')).includes('_ga'),'no GA cookie created by empty container');
  await browser('reload');await browser('wait','--fn','!!window.cmpManager || !!window.cmpFailure');assert.equal(await run('return window.cmpFailure'),null);
  assert.equal(await run("return cmpManager.getConsent('analytics')"),false,'persisted refusal restored');
  await run("cmpChoose(true);return true");await browser('reload');await browser('wait','--fn','!!window.cmpManager || !!window.cmpFailure');assert.equal(await run('return window.cmpFailure'),null);
  assert.equal(await run("return cmpManager.getConsent('analytics')"),true,'persisted grant restored by real CMP');
  await consent(c=>c.analytics===true,'persisted grant reported after reload');
  await browser('open',`${origin}/?cmp=1&storage=denied`);await browser('wait','--fn','!!window.cmpFailure');
  await consent(c=>c.analytics===false,'CMP storage exception reports denied');
  console.log('PASS: real Klaro 0.7.21 reports default, refusal, draft, grant, revocation, reload and blocked storage without stopping events');
 } else {
 const pause=()=>new Promise(r=>setTimeout(r,120));
 const clear=()=>run('dataLayer.length=0; return true');
 const ready=async()=>{for(let i=0;i<100;i++){const value=await run("return await call('state')");if(value?.allowed)return value;await new Promise(r=>setTimeout(r,20))}assert.fail('host handshake missing')};
 const empty=async label=>{await pause();assert.deepEqual(await run('return dataLayer'),[],label)};
 const purchase={event:'purchase',ecommerce:{currency:'CZK',transaction_id:'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',payment_type:'card',items:[{item_id:'product_1',item_name:'Ticket',price:10,quantity:1}]}};
 const lead={event:'generate_lead',currency:'CZK',value:0,lead_source:'waitlist',event_id:'cccccccc-cccc-cccc-cccc-cccccccccccc'};
 state=await ready();assert.deepEqual(state.consent,{analytics:false,marketing:false},'no signal from the host is denied');
 await run(`await call('view'); await call('confirmed',${JSON.stringify(purchase)}); await call('confirmed',${JSON.stringify(lead)}); return true`);await pause();
 let events=await run('return dataLayer');assert.ok(events.some(e=>e.event==='view_item')&&events.some(e=>e.event==='purchase')&&events.some(e=>e.event==='generate_lead'),'events reach the host without consent');
 console.log('PASS: host transport delivers the funnel and conversions without a consent signal');
 await clear();
 const payload={event:'purchase',email:'private@example.test',phone:'123',user_data:{email:'visitor@example.test',phone_number:'+420601234567',name:'private@example.test'},ecommerce:{currency:'CZK',transaction_id:'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',payment_type:'card',email:'private@example.test',items:[{item_id:'product_1',item_name:'Ticket',item_category:'Tickets',item_brand:'Summer',price:10,quantity:1,email:'private@example.test',phone:'123'}]}};
 await run(`await call('raw',${JSON.stringify(payload)}); return true`); await pause(); events=await run('return dataLayer');
 assert.deepEqual(events.find(e=>e.event==='purchase').ecommerce.items,[{item_id:'product_1',item_name:'Ticket',price:10,quantity:1,item_category:'Tickets',item_brand:'Summer'}]);
 assert.deepEqual(events.find(e=>e.event==='purchase').user_data,{email:'visitor@example.test',phone_number:'+420601234567'},'contact rebuilt to the two fields');assert.ok(!JSON.stringify(events).includes('private@example.test'),'other fields stripped');assert.deepEqual(events.at(-1),{user_data:null},'contact cleared after the event');
 await clear(); state=await run("return await call('state')");
 const envelope={namespace:'festapp-embed',protocol:1,type:'analytics',instance:state.instance,payload:{event:'page_view'}};
 await run(`window.dispatchEvent(new MessageEvent('message',{origin:'http://127.0.0.1:1',source:document.querySelector('iframe').contentWindow,data:${JSON.stringify(envelope)}}));window.dispatchEvent(new MessageEvent('message',{origin:${JSON.stringify(childOrigin)},source:window,data:${JSON.stringify(envelope)}})); return true`);
 await run(`await call('post',${JSON.stringify({...envelope,instance:'wrong'})});return true`);
 await empty('wrong origin, source or instance rejected');
 await run("FestappEmbed.setMeasurementConsent(document.querySelector('iframe'),false); return true");await pause();
 await run(`await call('post',${JSON.stringify(envelope)});return true`);await pause();assert.equal((await run('return dataLayer')).length,1,'refusal stops nothing');await clear();
 assert.equal(await run("return await call('error')"),false,'analytics error does not escape checkout caller');
 for(const action of ['visibility','pagehide','pageshow']) {await run(`await call('${action}');return true`);assert.equal((await run("return await call('state')")).enabled,true,`${action} keeps measurement`);}
 await run("await call('dispose');return true");await clear();await run("await call('view');return true");await empty('dispose blocks sends');
 const base={enabled:true,organization_allowed:true,runtime_supported:true,privacy_url:"https://organizer.example/privacy",eligible:true,valid_for_seconds:60};
 for(const key of ['enabled','organization_allowed','runtime_supported','eligible','valid_for_seconds']) {
  const policy={...base}; delete policy[key];
  await run(`await call('policy',${JSON.stringify(policy)});return true`);
  await run("await call('view');return true"); await empty(`incomplete policy ${key}`);
 }
 await run(`await call('policy',${JSON.stringify({...base,enabled:false})});return true`);
 await run("await call('view');return true"); await empty('disabled policy');
 await run(`await call('policy',${JSON.stringify({...base,valid_for_seconds:0.1})});return true`);
 await new Promise(r=>setTimeout(r,200)); await run("await call('view');return true"); await empty('expired policy');
 assert.equal(await run("return document.querySelectorAll('script[src]').length"),1,'fixture loads no analytics scripts');
 console.log('PASS: field stripping, forged messages, refusal, lifecycle, dispose, consumer errors and fail-closed policy');
 await browser('open',`${origin}/?private=1`);
 state=null; for(let i=0;i<30;i++){try{state=await run("return await call('state')");if(state?.instance)break}catch{} await new Promise(r=>setTimeout(r,100))} assert.ok(state?.instance,'private entry initialized');
 await run("await call('view');return true"); await empty('sanitized original private URL remains ineligible');
 assert.equal((await run("return await call('state')")).enabled,false,'original private entry fails closed after URL sanitized');
 console.log('PASS: private entry remains ineligible after URL sanitation');
 }
} finally { try{await browser('close')}catch{} await Promise.allSettled([host?.close(),child?.close()]); await rm(temp,{recursive:true,force:true}); }
