import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const script=readFileSync(new URL('../cloudflare_build.sh',import.meta.url),'utf8');
const scannerRoutes=readFileSync(new URL('../../web_client/src/services/scanner_routes.js',import.meta.url),'utf8').replaceAll('export function','function');
const workerSource=scannerRoutes+'\n'+script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1];
const {default:worker}=await import('data:text/javascript;base64,'+Buffer.from(workerSource).toString('base64'));
test('Flutter map documents allow OSM identification without overriding callback protection',async()=>{
 const html=readFileSync(new URL('../../web/index.html',import.meta.url),'utf8');
 const env={ASSETS:{fetch:async(request)=>new URL(request.url).pathname==='/flutter'
  ?new Response(html,{headers:{'content-type':'text/html'}}):new Response('',{status:404})}};
 for(const path of ['/2025we-copy-5e6268f4/map/overview','/app/google-auth']){
  const response=await worker.fetch(new Request('https://tenant.invalid'+path),env);
  assert.equal(response.status,200);
  // Document meta overrides HTTP headers. Inherit the host's default/browser
  // policy for maps and its explicit no-referrer for sensitive callbacks.
  assert.equal(/<meta\b[^>]*\bname\s*=\s*["']referrer["'][^>]*>/i.test(await response.text()),false);
  assert.equal(response.headers.get('referrer-policy'),path==='/app/google-auth'?'no-referrer':null);
 }
});
test('real generated hosting router chooses the correct callback adapter and disables proof caching',async()=>{
 const paths=[];const env={ASSETS:{fetch:async(request)=>{const p=new URL(request.url).pathname;paths.push(p);return new Response(p,{headers:{'content-type':'application/octet-stream'}});}}};
 for(const [path,entry]of [['/google-auth','/webclient'],['/app/google-auth','/flutter'],['/settings/mcp-connect','/webclient'],['/settings/connections','/webclient']]){
  const response=await worker.fetch(new Request('https://tenant.invalid'+path+'?google_code=proof&google_attempt=fixture'),env);
  assert.equal(await response.text(),entry);assert.equal(response.headers.get('cache-control'),'no-store');assert.equal(response.headers.get('referrer-policy'),'no-referrer');assert.equal(response.headers.get('location'),null);
 }
 assert.deepEqual(paths,['/webclient','/flutter','/webclient','/webclient']);
 const aasa=await worker.fetch(new Request('https://tenant.invalid/.well-known/apple-app-site-association'),env);assert.equal(aasa.headers.get('content-type'),'application/json');
});

test('Stripe private deep links reach Flutter before occasion lookup in both tenant modes', async t => {
 let lookups = 0;
 t.mock.method(globalThis, 'fetch', async () => {
  lookups++;
  return new Response('null', {headers: {'content-type': 'application/json'}});
 });
 const requests = [];
 const env = {SUPABASE_URL: 'https://api.example.invalid', SUPABASE_ANON_KEY: 'synthetic',
  ASSETS: {fetch: async request => {
   const url = new URL(request.url);
   requests.push(url);
   return url.pathname === '/flutter'
    ? new Response('Flutter shell', {headers: {'content-type': 'text/html'}})
    : new Response('Missing', {status: 404});
  }}};
 const policy = readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js', import.meta.url), 'utf8').replaceAll('export function ', 'function ');
 const ticketingSource = workerSource.replace('const IS_APP_SUPPORTED = true;', 'const IS_APP_SUPPORTED = false;').replace('// PUBLIC_OCCASION_ROUTE_POLICY', policy);
 const {default: ticketingWorker} = await import('data:text/javascript;base64,' + Buffer.from(ticketingSource).toString('base64'));
 for (const currentWorker of [worker, ticketingWorker]) {
  for (const prefix of ['', '/app']) {
   for (const suffix of ['/connect/callback', '/pay', '/return']) {
    const path = prefix + '/stripe' + suffix;
    const response = await currentWorker.fetch(new Request('https://tenant.invalid' + path + '?code=synthetic&state=fixture'), env);
    assert.equal(response.status, 200, path);
    assert.equal(await response.text(), 'Flutter shell', path);
    assert.equal(response.headers.get('cache-control'), 'no-store');
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer');
    assert.equal(response.headers.get('x-robots-tag'), 'noindex, nofollow');
    assert.equal(response.headers.get('location'), null);
   }
  }
 }
 assert.equal(lookups, 0, 'Stripe routes are not occasion slugs');
 assert.equal(requests.length, 12);
 assert.ok(requests.every(url => url.pathname === '/flutter' && url.search === ''), 'private query values never reach asset requests');
});


test('account connections stay in the web client on app and ticketing tenants', async () => {
 const policy=readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js',import.meta.url),'utf8').replaceAll('export function ','function ');
 for(const appSupported of [true,false]) {
  const source=workerSource.replace('const IS_APP_SUPPORTED = true;',`const IS_APP_SUPPORTED = ${appSupported};`).replace('// PUBLIC_OCCASION_ROUTE_POLICY',policy);
  const {default:current}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const env={ASSETS:{fetch:async request=>new Response(new URL(request.url).pathname)}};
  const response=await current.fetch(new Request('https://tenant.invalid/settings/connections'),env);
  assert.equal(response.status,200);assert.equal(await response.text(),'/webclient');
  assert.equal(response.headers.get('cache-control'),'no-store');
  assert.equal(response.headers.get('x-robots-tag'),'noindex, nofollow');
 }
});
