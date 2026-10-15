import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { getOccasionHref } from '../../web_client/src/components/occasion/occasion_link.js';

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const workerSource = script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]
  .replace('// SHARED_CATALOG_CLASSIFICATION', readFileSync(new URL('../../web_client/src/components/occasion/catalog.js', import.meta.url), 'utf8').replaceAll('export function', 'function'))
  .replace('const SITE_NAME = "Festapp";', 'const SITE_NAME = "vstupenky.online";');
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(workerSource).toString('base64'));
const shell = readFileSync(new URL('../../web_client/index.html', import.meta.url), 'utf8');
const env = {
  SUPABASE_URL: 'https://backend.invalid', SUPABASE_ANON_KEY: 'public-fixture', ORGANIZATION_ID: 3,
  ASSETS: { fetch: async request => {
    const path = new URL(request.url).pathname;
    return ['/webclient', '/flutter'].includes(path)
      ? new Response(path === '/webclient' ? shell : 'flutter app')
      : new Response('missing', { status: 404 });
  } },
};
const request = path => new Request('https://tickets.invalid' + path);
const occasions = [
  { title: 'Camp & <script>bad</script>', link: 'camp', form: { link: 'camp-registration' }, features: [{ code: 'form', is_enabled: true }] },
  { title: 'Program', link: 'program', features: [] },
  { title: 'External', link: 'external', features: [{ code: 'form', is_enabled: true, data: { use_external_form: true, external_form_link: 'https://organizer.invalid/register?a=1&b=2' } }] },
  { title: 'Unsafe URL', link: 'safe', features: [{ code: 'form', is_enabled: true, data: { use_external_form: true, external_form_link: 'javascript:alert(1)' } }] },
];

test('server HTML and sitemap agree with native card destinations, escape content and omit invented dates', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    assert.deepEqual(JSON.parse(options.body), { p_organization_id: 3, p_unit_id: null });
    return Response.json({ occasions });
  });
  const home = await worker.fetch(request('/'), env);
  const html = await home.text();
  assert.equal(home.status, 200);
  for (const occasion of occasions) {
    const href = getOccasionHref(occasion).replaceAll('&', '&amp;');
    assert.ok(html.includes(`<a href="${href}">`), href);
  }
  assert.ok(html.includes('Camp &amp; &lt;script&gt;bad&lt;/script&gt;'));
  assert.ok(!html.includes('<script>bad</script>'));
  assert.ok(!html.includes('href="javascript:'));
  const sitemap = await worker.fetch(request('/sitemap.xml'), env);
  const xml = await sitemap.text();
  assert.equal(sitemap.headers.get('content-type'), 'application/xml');
  assert.ok(xml.includes('https://tickets.invalid/form/camp-registration'));
  assert.ok(xml.includes('https://tickets.invalid/program/event'));
  assert.ok(!xml.includes('organizer.invalid'));
  assert.ok(!xml.includes('<lastmod>'));
});

test('catalog failure preserves the application shell', async t => {
  t.mock.method(globalThis, 'fetch', async () => new Response('unavailable', { status: 503 }));
  const response = await worker.fetch(request('/'), env);
  assert.equal(response.status, 200);
  assert.ok((await response.text()).includes('id="app"'));
});

test('form SEO escapes names and strips tracking parameters from canonical URLs', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    assert.equal(JSON.parse(options.body).p_link_slug, 'form-name');
    return Response.json({ title: 'A "quote" & <b>title</b>', description: 'Event description' });
  });
  const response = await worker.fetch(request('/form/form-name?source=mail'), env);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.ok(html.includes('<title>A &quot;quote&quot; &amp; &lt;b&gt;title&lt;/b&gt; - vstupenky.online</title>'));
  assert.ok(html.includes('href="https://tickets.invalid/form/form-name"'));
  assert.ok(!html.includes('source=mail'));
});

test('confirmed missing forms, unknown slugs and missing assets return 404; valid app routes remain usable', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) =>
    Response.json(JSON.parse(options.body).p_link_slug === 'valid-event' ? { title: 'Valid event' } : null));
  for (const path of ['/form/missing', '/unknown-slug', '/missing.svg', '/missing.png', '/form/']) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 404, path);
    assert.ok((await response.text()).includes('noindex'));
  }
  for (const path of ['/valid-event/event', '/unit/3/edit/orders', '/signup', '/login-qr', '/resetPassword']) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 200, path);
    assert.equal(await response.text(), 'flutter app');
  }
});

test('backend outages never turn an existing form or app route into a 404', async t => {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('network unavailable'); });
  for (const path of ['/form/valid-event', '/valid-event/event']) {
    assert.equal((await worker.fetch(request(path), env)).status, 200);
  }
});

const productionSource = workerSource.replace('const CANONICAL_ORIGIN = null;', 'const CANONICAL_ORIGIN = "https://vstupenky.online";')
  .replace('const ORGANIZERS_ENABLED = false;', 'const ORGANIZERS_ENABLED = true;');
const { default: productionWorker } = await import('data:text/javascript;base64,' + Buffer.from(productionSource).toString('base64'));

test('canonical host/protocol matrix preserves form and OAuth query parameters, previews stay isolated', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ title: 'Public form' }));
  for (const path of ['/', '/form/live?utm_source=seo-check&code=a%2Bb&state=x%2Fy', '/google-auth?google_code=proof&google_attempt=fixture']) {
    for (const origin of ['http://vstupenky.online', 'https://www.vstupenky.online', 'http://www.vstupenky.online']) {
      const response = await productionWorker.fetch(new Request(origin + path), env);
      assert.equal(response.status, 308);
      assert.equal(response.headers.get('location'), 'https://vstupenky.online' + path);
    }
    assert.equal((await productionWorker.fetch(new Request('https://vstupenky.online' + path), env)).status, 200);
  }
  const preview = await productionWorker.fetch(new Request('https://preview.pages.dev/'), env);
  assert.equal(preview.status, 200);
  assert.equal(preview.headers.get('location'), null);
  assert.equal(preview.headers.get('strict-transport-security'), null);
});

test('HSTS covers HTML, XML, missing assets, redirects and thrown asset failures, including HEAD', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ occasions: [] }));
  for (const path of ['/', '/missing.png', '/sitemap.xml', '/webclient']) {
    for (const method of ['GET', 'HEAD']) {
      const response = await productionWorker.fetch(new Request('https://vstupenky.online' + path, { method }), env);
      assert.equal(response.headers.get('strict-transport-security'), 'max-age=300');
      if (method === 'HEAD') assert.equal(await response.text(), '');
    }
  }
  const response = await productionWorker.fetch(new Request('https://vstupenky.online/'), {
    ASSETS: { fetch: async () => { throw new Error('asset outage'); } },
  });
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('strict-transport-security'), 'max-age=300');
});

test('organizer route serves its own HTML, uses apex in sitemap and deduplicates internal links', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ occasions: [...occasions, occasions[0]] }));
  const pageEnv = { ...env, ASSETS: { fetch: async request => new URL(request.url).pathname === '/organizers-page'
    ? new Response('<h1>Prodej vstupenek a registrace na akce</h1>') : env.ASSETS.fetch(request) } };
  const response = await productionWorker.fetch(new Request('https://vstupenky.online/pro-poradatele'), pageEnv);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Prodej vstupenek/);
  assert.equal((await worker.fetch(request('/pro-poradatele'), env)).status, 404);
  const xml = await (await productionWorker.fetch(new Request('https://preview.pages.dev/sitemap.xml'), pageEnv)).text();
  assert.ok(xml.includes('https://vstupenky.online/pro-poradatele'));
  assert.equal((xml.match(/<loc>https:\/\/vstupenky.online\/form\/camp-registration<\/loc>/g) || []).length, 1);
  assert.ok(!xml.includes('preview.pages.dev'));
});

test('server catalogue preserves undated records and orders present, upcoming and visible archive', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ occasions: [
    { title: 'Archive (Copy)', link: 'archive', start_time: '2020-01-01', end_time: '2020-01-02' },
    { title: 'Next', link: 'next', start_time: '2099-01-01', end_time: '2099-01-02' },
    { title: 'Current', link: 'current', start_time: '2000-01-01', end_time: '2099-01-02' },
    { title: 'No date', link: 'undated' },
  ] }));
  const html = await (await worker.fetch(request('/'), env)).text();
  assert.ok(html.indexOf('Current</a>') < html.indexOf('Next</a>'));
  assert.ok(html.indexOf('Next</a>') < html.indexOf('Archive (Copy)</a>'));
  assert.match(html, /<section class="catalog-archive"><h2>Proběhlé události<\/h2>/);
  assert.ok(html.includes('No date</a>'));
  assert.ok(html.includes('data-server-catalog="ready"'));
});


test('malformed catalogue payload is unavailable rather than an empty catalogue', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ error: 'unexpected payload' }));
  const html = await (await worker.fetch(request('/'), env)).text();
  assert.ok(html.includes('data-server-catalog="unavailable"'));
  assert.ok(!html.includes('Zatím zde nejsou žádné akce.'));
});


test('organizer route is preserved by the real ticket-only policy', async () => {
  const source = productionSource.replace('const IS_APP_SUPPORTED = true;', 'const IS_APP_SUPPORTED = false;')
    .replace('// PUBLIC_OCCASION_ROUTE_POLICY', readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js', import.meta.url), 'utf8').replaceAll('export function ', 'function '));
  const { default: ticketWorker } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  const pageEnv = { ...env, ASSETS: { fetch: async request => new URL(request.url).pathname === '/organizers-page'
    ? new Response('<h1>Prodej vstupenek a registrace na akce</h1>') : env.ASSETS.fetch(request) } };
  const response = await ticketWorker.fetch(new Request('https://vstupenky.online/pro-poradatele'), pageEnv);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Prodej vstupenek/);
});


test('server archive stays visible and groups large multi-year archives', async t => {
  const past = Array.from({length: 9}, (_, i) => ({
    ...occasions[0], title: `Archive ${i}`, link: `archive-${i}`,
    start_time: `${i < 5 ? 2025 : 2024}-05-01T00:00:00Z`,
    end_time: `${i < 5 ? 2025 : 2024}-05-02T00:00:00Z`,
  }));
  t.mock.method(globalThis, 'fetch', async () => Response.json({occasions: past}));
  const html = await (await worker.fetch(request('/'), env)).text();
  assert.ok(!html.includes('<details'));
  assert.ok(html.includes('<h3>2025</h3>'));
  assert.ok(html.includes('<h3>2024</h3>'));
  assert.ok(html.indexOf('<h3>2025') < html.indexOf('<h3>2024'));
  for (const occasion of past) assert.ok(html.includes(occasion.title));
});

test('independent customer overview serves private web shell without resolving a form', async t => {
 t.mock.method(globalThis,'fetch',async()=>{throw new Error('order shell must not query public form metadata');});
 const response=await worker.fetch(request('/order?order_id=1&token=secret'),env);
 assert.equal(response.status,200);
 assert.equal(response.headers.get('cache-control'),'no-store');
 assert.equal(response.headers.get('referrer-policy'),'no-referrer');
 assert.equal(response.headers.get('x-robots-tag'),'noindex, nofollow');
 assert.notEqual(await response.text(),'flutter app');
});

test('retired personal form query links return gone without redirect or data lookup', async t => {
  t.mock.method(globalThis, 'fetch', async () => {throw new Error('no customer/form lookup');});
  for (const query of ['order_id=1&token=secret','offer_id=offer&admin=1','waitlist=1&token=secret']) {
    const response=await productionWorker.fetch(new Request('https://vstupenky.online/form/test?'+query),env);
    assert.equal(response.status,410);assert.equal(response.headers.get('location'),null);
    assert.equal(response.headers.get('cache-control'),'no-store');
  }
});
