import { helpActionWorkerSource } from '../lib/help_action_worker_source.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const profiles = Object.fromEntries(['webclient','flutter','auth_bridge','organizers','none','static-test'].map(profile => [profile, {policy: `base-uri 'self'; object-src 'none'; script-src 'self' 'sha256-${profile}'; script-src-attr 'none'; report-uri /_security/csp-report?profile=${profile}; report-to csp-${profile}`} ]));
const scannerRoutes = readFileSync(new URL('../../web_client/src/services/scanner_routes.js', import.meta.url), 'utf8').replaceAll('export function', 'function');
const source = scannerRoutes + '\n' + script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1].replace('// HELP_ACTION_ROUTE_POLICY', () => helpActionWorkerSource)
 .replace('// SHARED_PUBLIC_PAGE_SEO',readFileSync(new URL('../../web_client/src/services/public_page_seo.js', import.meta.url),'utf8').replaceAll('export function','function'))
 .replace('const CSP_MANIFEST = { profiles: {}, documents: {} };', () => `const CSP_MANIFEST = ${JSON.stringify({profiles, documents:{'privacy/index.html':{profile:'static-test'}}})};`)
 .replace('const MARKETING = {enabled:false,pages:[],sitemapPaths:["/"]};', 'const MARKETING = {enabled:true,pages:[{id:"home",path:"/",asset:"/organizers-page"}],sitemapPaths:["/","/events"]};');
const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const env = {ASSETS:{fetch:async req => {
 const path = new URL(req.url).pathname;
 return ['/webclient','/flutter','/auth_bridge','/organizers-page','/privacy/'].includes(path) ? new Response('<html>shell</html>', {headers:{'content-type':'text/html'}}) : new Response('missing',{status:404});
}}};
const request = path => new Request('https://fixture.invalid' + path);
test('all actual HTML router branches including bridge, callback, fallback and static responses carry their document policy', async () => {
 for (const [path, profile] of [['/','organizers'],['/form/example','webclient'],['/admin','flutter'],['/app/google-auth','flutter'],['/google-auth','webclient'],['/settings/mcp-connect','webclient'],['/settings/connections','webclient'],['/auth_bridge.html','auth_bridge'],['/events','webclient'],['/unknown/deep','flutter'],['/missing.js','none'],['/privacy/','static-test'],['/flutter?pwa-cache=1','flutter']]) {
  const res = await worker.fetch(request(path), env);
  assert.equal(res.headers.get('content-security-policy'), "base-uri 'self'; object-src 'none'", path);
  assert.equal(res.headers.get('content-security-policy-report-only'), profiles[profile].policy, path);
  assert.match(res.headers.get('reporting-endpoints'), new RegExp(`csp-${profile}=`), path);
 }
});
function report(body, mime='application/csp-report', extra={}) {
 return worker.fetch(new Request('https://fixture.invalid/_security/csp-report?profile=webclient', {method:'POST', headers:{'content-type':mime}, body:typeof body === 'string' ? body : JSON.stringify(body), ...extra}), env);
}
test('report route enforces method, MIME, bounded streams, JSON shape and batch limits', async () => {
 assert.equal((await worker.fetch(request('/_security/csp-report'),env)).status,405);
 assert.equal((await report('{}','text/plain')).status,415);
 assert.equal((await report('broken')).status,400);
 assert.equal((await report({})).status,400);
 assert.equal((await report(' '.repeat(32769))).status,413);
 const stream = new ReadableStream({start(c){c.enqueue(new Uint8Array(20000));c.enqueue(new Uint8Array(20000));c.close();}});
 assert.equal((await report(stream,'application/json',{body:stream,duplex:'half'})).status,413);
 assert.equal((await report(Array(11).fill({type:'csp-violation',body:{effectiveDirective:'script-src'}}), 'application/reports+json')).status,400);
});
test('accepted reports log only bounded fields and discard tokens, sample, referrer, raw body and credentials', async t => {
 const logs=[];t.mock.method(console,'info', (...args)=>logs.push(args));
 const body={'effective-directive':'script-src-elem','blocked-uri':'https://user:password@cdn.example/path-secret?token=private#fragment', 'document-uri':'https://fixture.invalid/order/token-secret',referrer:'private-referrer','script-sample':'sample-secret',disposition:'report'};
 const res=await report({'csp-report':body});
 assert.equal(res.status,204);assert.equal(res.headers.get('cache-control'),'no-store');
 assert.deepEqual(logs[0],['csp-violation',{directive:'script-src-elem',disposition:'report',profile:'webclient',source:'https://cdn.example'}]);
 assert.doesNotMatch(JSON.stringify(logs),/private|secret|password|fragment|referrer|sample/);
 assert.equal((await report([{type:'csp-violation',body:{effectiveDirective:'script-src-attr',blockedURL:'inline',disposition:'enforce'}}],'application/reports+json')).status,204);
 for(let i=0;i<30;i++) await report({'csp-report':body});
 assert.ok(logs.length<=20,'per-isolate logging cap');
});

test('enforcing manifest moves script policy to enforcement without a duplicate Report-Only header', async () => {
 const enforcing = source.replace('const CSP_MANIFEST = ' + JSON.stringify({profiles, documents:{'privacy/index.html':{profile:'static-test'}}}) + ';', () => 'const CSP_MANIFEST = ' + JSON.stringify({mode:'enforce',profiles,documents:{}}) + ';');
 const {default: active} = await import('data:text/javascript;base64,' + Buffer.from(enforcing).toString('base64'));
 for (const [path,profile] of [['/','organizers'],['/admin','flutter'],['/auth_bridge','auth_bridge'],['/unknown','flutter']]) {
  const response = await active.fetch(request(path),env);
  assert.equal(response.headers.get('content-security-policy'),profiles[profile].policy);
  assert.equal(response.headers.get('content-security-policy-report-only'),null);
 }
});
