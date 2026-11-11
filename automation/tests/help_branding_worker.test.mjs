import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import vm from 'node:vm';
import {spawnSync} from 'node:child_process';

test('an installed worker serves help branding without an application version report',async t=>{
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'help-brand-worker-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 for(const [name,body]of[['flutter','flutter'],['webclient','app'],['main.dart.js','main']])fs.writeFileSync(path.join(root,name),body);
 const generated=spawnSync(process.execPath,['automation/generate_pwa_service_worker.mjs',root,'1.0.0+1'],{encoding:'utf8'});
 assert.equal(generated.status,0,generated.stderr);
 const handlers={},requests=[];
 const body='<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1 1"></svg>';
 vm.runInNewContext(fs.readFileSync(path.join(root,'festapp_service_worker.js'),'utf8'),{
  URL,Request,Response,Promise,setTimeout,clearTimeout,
  fetch:async request=>{requests.push(request.url);return new Response(body,{headers:{'content-type':'image/svg+xml'}});},
  caches:{open(){assert.fail('Public help must not enter a version-pinned application cache');}},
  self:{location:{origin:'https://app.test'},clients:{get(){assert.fail('Help branding must not require a client version');}},addEventListener:(type,handler)=>{handlers[type]=handler;}},
 });
 for(const base of ['/napoveda/assets/','/help/assets/','/co-je-nove/_assets/'])for(const name of ['brand-logo.svg','brand-logo-light.svg','brand-symbol.svg','brand-wordmark.svg','brand-wordmark-stacked.svg']){
  let pending;
  handlers.fetch({request:new Request('https://app.test'+base+name),clientId:'help-without-app-version',respondWith:value=>{pending=value;}});
  const response=await pending;assert.equal(response.status,200);assert.equal(await response.text(),body);
 }
 assert.equal(requests.length,15);
});
