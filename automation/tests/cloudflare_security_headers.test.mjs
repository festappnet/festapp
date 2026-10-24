import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const scannerRoutes = readFileSync(new URL('../../web_client/src/services/scanner_routes.js', import.meta.url), 'utf8').replaceAll('export function', 'function');
const source = scannerRoutes + '\n' + script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]
 .replace('// SHARED_PUBLIC_PAGE_SEO',readFileSync(new URL('../../web_client/src/services/public_page_seo.js',import.meta.url),'utf8').replaceAll('export function','function'));
const {default: worker} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const origin = 'https://tenant.invalid';
const env = {ASSETS: {fetch: async request => {
  const path = new URL(request.url).pathname;
  return new Response(path, {headers: {'content-type': path.endsWith('.js') ? 'application/javascript' : 'text/html'}});
}}};

function assertPolicy(response) {
  assert.equal(response.headers.get('content-security-policy'), "base-uri 'self'; object-src 'none'");
  assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
}

test('generated Pages worker secures HTML and assets while preserving route bodies', async () => {
  for (const [path, body] of [
    ['/', '/webclient'],
    ['/login', '/flutter'], ['/auth_bridge', '/auth_bridge'], ['/unknown', '/unknown'],
    ['/web-assets/app.js', '/web-assets/app.js'], ['/main.dart.js', '/main.dart.js'], ['/embed.js', '/embed.js'],
  ]) {
    const response = await worker.fetch(new Request(origin + path), env);
    assertPolicy(response);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), body);
    if (path === '/main.dart.js' || path === '/embed.js') assert.equal(response.headers.get('cache-control'), 'no-cache, must-revalidate');
  }
  const temporary=await worker.fetch(new Request(origin+'/form/example'),env);
  assertPolicy(temporary);
  assert.equal(temporary.status,503);
  assert.equal(temporary.headers.get('retry-after'),'60');
  assert.match(temporary.headers.get('cache-control'),/no-store/);
  assert.equal(await temporary.text(),'/webclient');
});

test('empty form slug returns a secured 404 rather than a successful shell', async () => {
  const response = await worker.fetch(new Request(origin + '/form/'), env);
  assertPolicy(response);
  assert.equal(response.status, 404);
  assert.match(await response.text(), /noindex/);
});

test('policy wrapping preserves redirect status, activation CORS and OAuth cache controls', async () => {
  const redirect = await worker.fetch(new Request(origin + '/flutter'), env);
  assertPolicy(redirect);
  assert.equal(redirect.status, 301);
  assert.equal(redirect.headers.get('location'), origin + '/');

  const preflight = await worker.fetch(new Request(origin + '/backend-activation.json', {method: 'OPTIONS'}), env);
  assertPolicy(preflight);
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get('access-control-allow-origin'), '*');
  assert.equal(preflight.headers.get('access-control-allow-methods'), 'GET, HEAD, OPTIONS');
  assert.equal(await preflight.text(), '');

  const activation = await worker.fetch(new Request(origin + '/backend-activation.json'), env);
  assertPolicy(activation);
  assert.equal(activation.headers.get('access-control-allow-origin'), '*');
  assert.equal(activation.headers.get('cache-control'), 'no-store, max-age=0');

  const oauth = await worker.fetch(new Request(origin + '/google-auth?google_code=proof'), env);
  assertPolicy(oauth);
  assert.equal(oauth.headers.get('cache-control'), 'no-store');
  assert.equal(oauth.headers.get('referrer-policy'), 'no-referrer');
});

test('organization administration deep links serve Flutter without an occasion lookup', async t => {
  let lookups = 0;
  t.mock.method(globalThis, 'fetch', async () => {
    lookups++;
    return new Response('null', {headers: {'content-type': 'application/json'}});
  });
  const production = {
    SUPABASE_URL: 'https://api.example.invalid', SUPABASE_ANON_KEY: 'synthetic',
    ASSETS: {fetch: async request => new URL(request.url).pathname === '/flutter'
      ? new Response('Flutter shell', {headers: {'content-type': 'text/html'}})
      : new Response('Missing', {status: 404})},
  };
  const ticketingSource = source
    .replace('const IS_APP_SUPPORTED = true;', 'const IS_APP_SUPPORTED = false;')
    .replace('// PUBLIC_OCCASION_ROUTE_POLICY', readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js', import.meta.url), 'utf8').replaceAll('export function ', 'function '));
  const {default: ticketingWorker} = await import('data:text/javascript;base64,' + Buffer.from(ticketingSource).toString('base64'));
  for (const currentWorker of [worker, ticketingWorker]) {
    for (const path of ['/organizationEdit', '/organizationEdit/3', '/organizationEdit/3/?tab=verification']) {
      const response = await currentWorker.fetch(new Request(origin + path), production);
      assert.equal(response.status, 200, path);
      assert.equal(await response.text(), 'Flutter shell', path);
      assertPolicy(response);
    }
  }
  assert.equal(lookups, 0, 'platform administration is not an occasion slug');
});

test('help routes use their bound HTML profile, canonical paths and sitemap entries', async t => {
  const helpManifest = {profiles: {'help-index':{policy:'help-index-policy'},'help-webnode':{policy:'help-webnode-policy'}},documents: {'napoveda/index.html': {profile:'help-index'}, 'napoveda/webnode/index.html': {profile:'help-webnode'}}};
  const helpSource = source.replace('const CSP_MANIFEST = { profiles: {}, documents: {} };', 'const CSP_MANIFEST = ' + JSON.stringify(helpManifest) + ';');
  const {default: helpWorker} = await import('data:text/javascript;base64,' + Buffer.from(helpSource).toString('base64'));
  t.mock.method(globalThis, 'fetch', async () => new Response('[]', {headers:{'content-type':'application/json'}}));
  for (const route of ['/napoveda/', '/napoveda/webnode/']) {
    const response = await helpWorker.fetch(new Request(origin + route), env);
    assert.equal(response.status,200); assertPolicy(response); assert.equal(await response.text(),route);
    assert.match(response.headers.get('content-security-policy-report-only'),/help-/);
  }
  const redirect = await helpWorker.fetch(new Request(origin + '/napoveda/webnode'),env);
  assert.equal(redirect.status,308); assert.equal(redirect.headers.get('location'),origin + '/napoveda/webnode/');
  for (const current of [worker,helpWorker]) {
    const absent = await current.fetch(new Request(origin + '/napoveda/unknown/'),env);
    assert.equal(absent.status,404); assert.match(await absent.text(),/noindex/);
  }
  const sitemap = await (await helpWorker.fetch(new Request(origin + '/sitemap.xml'),env)).text();
  assert.match(sitemap,/<loc>https:\/\/tenant\.invalid\/napoveda\/webnode\/<\/loc>/);
});
