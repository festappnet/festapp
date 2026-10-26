import { helpActionWorkerSource } from '../lib/help_action_worker_source.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const read = file => readFileSync(new URL(file, import.meta.url), 'utf8');
const template = read('../cloudflare_build.sh').match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource);
const scanner = read('../../web_client/src/services/scanner_routes.js').replaceAll('export function', 'function');
const policy = read('../../web_client/src/services/public_occasion_routes.js').replaceAll('export function', 'function');
const manifest = {profiles:{help:{policy:"default-src 'self'"}},documents:{'napoveda/index.html':{profile:'help'},'napoveda/objednavky/index.html':{profile:'help'}}};

test('cached help navigations receive the real document in both tenant modes', async()=>{
 for(const supported of [true,false]) {
  const source = scanner+'\n'+template.replace('const IS_APP_SUPPORTED = true;',`const IS_APP_SUPPORTED = ${supported};`)
   .replace('// PUBLIC_OCCASION_ROUTE_POLICY',policy)
   .replace('const CSP_MANIFEST = { profiles: {}, documents: {} };','const CSP_MANIFEST = '+JSON.stringify(manifest)+';');
  const {default:worker} = await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  for(const path of ['/napoveda/','/napoveda/objednavky/']) for(const headers of [{'if-none-match':'"cached-help"'},{'if-modified-since':'Sat, 24 Oct 2026 12:00:00 GMT'}]) {
   const env={ASSETS:{fetch:async request=>{
    assert.equal(new URL(request.url).pathname,path);
    if(request.headers.has('if-none-match')||request.headers.has('if-modified-since')) return new Response(null,{status:304});
    return new Response('<h1>Correct help document</h1>',{headers:{'content-type':'text/html',etag:'"cached-help"'}});
   }}};
   const response=await worker.fetch(new Request('https://tenant.invalid'+path,{headers}),env);
   assert.equal(response.status,200,JSON.stringify({supported,path,headers}));
   assert.match(await response.text(),/Correct help document/);
  }
 }
});
