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


test('global responsive adapters use the canonical distinct vector masters', t => {
 const root=fs.mkdtempSync(path.join(os.tmpdir(),'global-brand-'));t.after(()=>fs.rmSync(root,{recursive:true,force:true}));
 const brand='assets/brand/festapp-tickets';
 fs.mkdirSync(path.join(root,'assets/brand'),{recursive:true});
 fs.cpSync(brand,path.join(root,brand),{recursive:true});
 for (const style of ['spinner','brand-outline']) {
 const result=spawnSync('python3',['automation/configure_brand_assets.py','--root',root,
  '--logo',brand+'/festapp-tickets-header.svg','--dark-logo',brand+'/festapp-tickets-header-dark.svg',
  '--loading-style',style,'--icon-dir',brand+'/web-icons',
  '--animation',brand+'/festapp-tickets-loading.svg','--dark-animation',brand+'/festapp-tickets-loading-dark.svg'],{encoding:'utf8'});
 assert.equal(result.status,0,result.stderr);
 for(const [adapter,master] of [['brand-symbol','symbol'],['brand-wordmark-stacked','wordmark-stacked-header'],['brand-wordmark','wordmark-horizontal']]) {
  assert.deepEqual(fs.readFileSync(path.join(root,'web_client/public',adapter+'.svg')),fs.readFileSync(brand+'/festapp-tickets-'+master+'-dark.svg'));
 }
 const stacked=fs.readFileSync(brand+'/festapp-tickets-wordmark-dark.svg','utf8');
 const horizontal=fs.readFileSync(brand+'/festapp-tickets-wordmark-horizontal-dark.svg','utf8');
 const glyphs=svg=>[...svg.matchAll(/<(?:[\w-]+:)?path\b[^>]*\bd="([^"]+)"/g)].map(match=>match[1]);
 assert.ok(glyphs(stacked).length>0);
 assert.deepEqual(glyphs(horizontal),glyphs(stacked));
 const adapted=fs.readFileSync(path.join(root,'web_client/public/brand-wordmark-stacked.svg'),'utf8');
 assert.deepEqual(glyphs(adapted),glyphs(stacked),'Header fitting preserves every canonical outlined glyph');
 assert.doesNotMatch(adapted,/<(?:[\w-]+:)?(?:text|image)\b/);
 if (style === 'brand-outline') {
  const animation=fs.readFileSync(path.join(root,'web/loading-animation.svg'),'utf8');
  assert.equal(animation,fs.readFileSync(brand+'/festapp-tickets-loading-dark.svg','utf8'));
  assert.match(animation,/outline-ticket/);
  assert.match(animation,/fill-center/);
  assert.match(animation,/prefers-reduced-motion/);
  assert.match(animation,/outline-name/);
  assert.match(animation,/fill-domain/);
  assert.doesNotMatch(animation,/vstupenky/);
 }
 }


});
