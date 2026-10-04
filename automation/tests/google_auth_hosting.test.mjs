import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const script=readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
const workerSource=script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1];
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(workerSource).toString('base64'));
test('real generated hosting router chooses the correct callback adapter and disables proof caching',async()=>{
 const paths=[];const env={ASSETS:{fetch:async(request)=>{const p=new URL(request.url).pathname;paths.push(p);return new Response(p,{headers:{'content-type':'application/octet-stream'}});}}};
 for(const [path,entry]of [['/google-auth','/webclient'],['/app/google-auth','/flutter']]){
  const response=await worker.fetch(new Request('https://tenant.invalid'+path+'?google_code=proof&google_attempt=fixture'),env);
  assert.equal(await response.text(),entry);assert.equal(response.headers.get('cache-control'),'no-store');assert.equal(response.headers.get('referrer-policy'),'no-referrer');assert.equal(response.headers.get('location'),null);
 }
 assert.deepEqual(paths,['/webclient','/flutter']);
 const aasa=await worker.fetch(new Request('https://tenant.invalid/.well-known/apple-app-site-association'),env);assert.equal(aasa.headers.get('content-type'),'application/json');
});
