import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const html=fs.readFileSync(new URL('../../web/index.html',import.meta.url),'utf8');
const code=html.match(/<script>(\s*\/\/ Check for redirect query param[\s\S]*?)<\/script>/)[1];
test('help login target survives shell bootstrap; legacy Flutter clean URLs still restore',()=>{
 for(const intent of ['seating','scanner-settings']) for(const path of ['/login','/app/login','/flutter']){
  const writes=[];const location=new URL('https://tenant.invalid'+path+'?redirect='+encodeURIComponent('/help-action/'+intent));
  vm.runInNewContext(code,{URLSearchParams,window:{location,history:{replaceState:(_,__,value)=>writes.push(value)}},console:{log(){}}});
  assert.deepEqual(writes,path==='/flutter'?['/help-action/'+intent]:[],path);
 }
});
test('help login links reach Flutter in app and ticketing tenant modes',async()=>{
 const build=fs.readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
 const scanner=fs.readFileSync(new URL('../../web_client/src/services/scanner_routes.js',import.meta.url),'utf8').replaceAll('export function','function');
 const policy=fs.readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js',import.meta.url),'utf8').replaceAll('export function ','function ');
 for(const supported of [true,false]) for(const intent of ['seating','scanner-settings']){
  const source=scanner+'\n'+build.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('const IS_APP_SUPPORTED = true;',`const IS_APP_SUPPORTED = ${supported};`).replace('// PUBLIC_OCCASION_ROUTE_POLICY',policy);
  const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const requested=[];const env={ASSETS:{fetch:async request=>{requested.push(new URL(request.url).pathname);return new Response('Flutter shell',{headers:{'content-type':'text/html'}});}}};
  const response=await worker.fetch(new Request('https://tenant.invalid/login?redirect='+encodeURIComponent('/help-action/'+intent)),env);
  assert.equal(response.status,200);assert.equal(await response.text(),'Flutter shell');assert.equal(response.headers.get('location'),null);assert.ok(requested.includes('/flutter'));
 }
});
