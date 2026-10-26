import { helpActionWorkerSource } from '../lib/help_action_worker_source.mjs';
import { helpActionFlutterPath } from '../../web_client/src/services/help_action_routes.js';
import { organizerCreateFlutterPath, ORGANIZER_CREATE_ACTION } from '../../web_client/src/services/organizer_entry.js';
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
const html=fs.readFileSync(new URL('../../web/index.html',import.meta.url),'utf8');
const code=html.match(/<script>(\s*\/\/ Check for redirect query param[\s\S]*?)<\/script>/)[1];
test('the actual Flutter bootstrap restores organizer creation continuation',()=>{
 const writes=[];
 const location=new URL(organizerCreateFlutterPath(),'https://tenant.invalid');
 vm.runInNewContext(code,{URLSearchParams,window:{location,history:{replaceState:(_,__,value)=>writes.push(value)}},console:{log(){}}});
 assert.equal(writes.length,1);
 const restored=new URL(writes[0],location.origin);
 assert.equal(restored.pathname,'/login');
 assert.equal(restored.searchParams.get('redirect'),ORGANIZER_CREATE_ACTION);
});
test('help login target survives shell bootstrap; legacy Flutter clean URLs still restore',()=>{
 for(const intent of ['seating','scanner-settings']) for(const path of ['/login','/app/login','/flutter']){
  const writes=[];const location=new URL('https://tenant.invalid'+path+'?redirect='+encodeURIComponent('/help-action/'+intent));
  vm.runInNewContext(code,{URLSearchParams,window:{location,history:{replaceState:(_,__,value)=>writes.push(value)}},console:{log(){}}});
  assert.deepEqual(writes,path==='/flutter'?['/help-action/'+intent]:[],path);
 }
});
test('existing help login links enter web authentication in app and ticketing tenant modes',async()=>{
 const build=fs.readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
 const scanner=fs.readFileSync(new URL('../../web_client/src/services/scanner_routes.js',import.meta.url),'utf8').replaceAll('export function','function');
 const policy=fs.readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js',import.meta.url),'utf8').replaceAll('export function ','function ');
 for(const supported of [true,false]) for(const intent of ['organization','bank-accounts','forms','seating','tickets','products','orders','report','settings','scanner-settings']){
  const source=scanner+'\n'+build.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource).replace('const IS_APP_SUPPORTED = true;',`const IS_APP_SUPPORTED = ${supported};`).replace('// PUBLIC_OCCASION_ROUTE_POLICY',policy);
  const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const requested=[];const env={ASSETS:{fetch:async request=>{requested.push(new URL(request.url).pathname);return new Response('Flutter shell',{headers:{'content-type':'text/html'}});}}};
  const response=await worker.fetch(new Request('https://tenant.invalid/login?redirect='+encodeURIComponent('/help-action/'+intent)),env);
  assert.equal(response.status,302);assert.equal(response.headers.get('location'),'https://tenant.invalid/events?help='+intent);assert.equal(requested.length,0);
  const entry=await worker.fetch(new Request(response.headers.get('location')),env);assert.equal(entry.status,200);assert.ok(requested.includes('/webclient'));
 }
});

test('authenticated web handoff restores login intent exactly once before Flutter bootstrap',()=>{
 const writes=[];
 const location=new URL(helpActionFlutterPath('orders'),'https://tenant.invalid');
 vm.runInNewContext(code,{URLSearchParams,window:{location,history:{replaceState:(_,__,value)=>writes.push(value)}},console:{log(){}}});
 assert.deepEqual(writes,['/login?redirect=%2Fhelp-action%2Forders']);
});


test('legacy help adapters reject arbitrary and malformed destinations',async()=>{
 const script=fs.readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
 const scanner=fs.readFileSync(new URL('../../web_client/src/services/scanner_routes.js',import.meta.url),'utf8').replaceAll('export function','function');
 const source=scanner+'\n'+script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY',()=>helpActionWorkerSource);
 const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
 const env={ASSETS:{fetch:async()=>new Response('web login',{headers:{'content-type':'text/html'}})}};
 for(const target of ['/help-action/unknown','/help-action/orders?next=x','/help-action/orders#x','https://evil.invalid/help-action/orders','//evil.invalid/help-action/orders']){
  const response=await worker.fetch(new Request('https://tenant.invalid/login?redirect='+encodeURIComponent(target)),env);
  assert.equal(response.status,200,target);assert.equal(response.headers.get('location'),null,target);
 }
});
