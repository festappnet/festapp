import {readConfig,resolveContext,publicManifest} from '../release/organizers/context.mjs';
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { getOccasionHref } from '../../web_client/src/components/occasion/occasion_link.js';

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const scannerSource = readFileSync(new URL('../../web_client/src/services/scanner_routes.js', import.meta.url), 'utf8').replaceAll('export function', 'function');
const workerSource = scannerSource + '\n' + script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]
  .replace('// SHARED_PUBLIC_PAGE_SEO', readFileSync(new URL('../../web_client/src/services/public_page_seo.js', import.meta.url), 'utf8').replaceAll('export function', 'function'))
  .replace('// SHARED_CATALOG_CLASSIFICATION', readFileSync(new URL('../../web_client/src/components/occasion/catalog.js', import.meta.url), 'utf8').replaceAll('export function', 'function'))
  .replace('const SITE_NAME = "Festapp";', 'const SITE_NAME = "vstupenky.online";');
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(workerSource).toString('base64'));
const shell = readFileSync(new URL('../../web_client/index.html', import.meta.url), 'utf8');
const env = {
  SUPABASE_URL: 'https://backend.invalid', SUPABASE_ANON_KEY: 'public-fixture', ORGANIZATION_ID: 3,
  ASSETS: { fetch: async request => {
    const path = new URL(request.url).pathname;
    return ['/webclient', '/flutter', '/organizers-page'].includes(path)
      ? new Response(path === '/webclient' ? shell : path === '/organizers-page' ? '<h1>Marketing</h1>' : 'flutter app')
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
  // A form without an event image must advertise the published site icon.
  for (const [attribute, prefix] of [['property', 'og'], ['name', 'twitter']]) {
    assert.ok(html.includes(`${attribute}="${prefix}:image" content="https://tickets.invalid/android-chrome-512x512.png"`));
  }
});

test('form HTML identifies the event when forms share a generic registration title', async t => {
  for (const title of ['Postní duchovní obnova s AKH', 'Ples AKH 2026']) {
    t.mock.method(globalThis, 'fetch', async () => Response.json({
      title, form_title: 'Registration', form_link: 'registration', description: 'Event details',
    }));
    const response = await worker.fetch(request('/form/registration'), env);
    const html = await response.text();
    assert.ok(html.includes(`<title>${title} - Registration - vstupenky.online</title>`));
    assert.ok(html.includes(`<h1>${title} - Registration</h1>`));
    assert.ok(html.includes(`property="og:title" content="${title} - Registration - vstupenky.online"`));
    t.mock.restoreAll();
  }
});

test('public page social images use a published fallback and preserve event images', async t => {
  const pageEnv = { ...env, ASSETS: { fetch: async () => new Response(shell) } };
  for (const image of [undefined, '', 'javascript:alert(1)', 'https://img.festapp.net/event.jpg']) {
    t.mock.method(globalThis, 'fetch', async () => Response.json({ title: 'Public event', image }));
    for (const path of ['/form/public-event', '/public-event/event']) {
      const response = await worker.fetch(request(path), pageEnv);
      assert.equal(response.status, 200);
      const html = await response.text();
      const expected = image?.startsWith('https:') ? image : 'https://tickets.invalid/android-chrome-512x512.png';
      for (const prefix of ['og', 'twitter']) {
        const attribute = prefix === 'twitter' ? 'name' : 'property';
        assert.ok(html.includes(`<meta ${attribute}="${prefix}:image" content="${expected}">`), `${path}: missing ${prefix} image ${expected}`);
      }
      if (!image?.startsWith('https:')) {
        const asset = new URL('../../web_client/public' + new URL(expected).pathname, import.meta.url);
        assert.ok(readFileSync(asset).length > 0, 'fallback image must be published');
      }
    }
  }
});

test('confirmed missing forms, unknown slugs and missing assets return 404; valid app routes remain usable', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) =>
    Response.json(JSON.parse(options.body).p_link_slug === 'valid-event' ? { title: 'Valid event' } : null));
  for (const path of ['/form/missing', '/unknown-slug', '/missing.svg', '/missing.png', '/form/']) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 404, path);
    assert.ok((await response.text()).includes('noindex'));
  }
  for (const path of ['/unit/3/edit/orders', '/signup', '/resetPassword']) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 200, path);
    assert.equal(await response.text(), 'flutter app');
  }
});

test('backend outages never turn an existing form or app route into a 404', async t => {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('network unavailable'); });
  for (const path of ['/form/valid-event', '/valid-event/event']) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 503);
    assert.equal(response.headers.get('retry-after'), '60');
    assert.match(response.headers.get('cache-control'), /no-store/);
    if (path.startsWith('/form/')) assert.ok((await response.text()).includes('href="https://tickets.invalid' + path + '"'));
  }
});

const productionSource = workerSource.replace('const CANONICAL_ORIGIN = null;', 'const CANONICAL_ORIGIN = "https://vstupenky.online";')
  .replace('const MARKETING = {enabled:false,pages:[],sitemapPaths:["/"]};', `const MARKETING = ${JSON.stringify(publicManifest(resolveContext(readConfig(new URL('../project.conf',import.meta.url)))))};`);
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
  const response = await productionWorker.fetch(new Request('https://vstupenky.online/'), pageEnv);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Prodej vstupenek/);
  assert.equal((await worker.fetch(request('/pro-poradatele'), env)).status, 404);
  const xml = await (await productionWorker.fetch(new Request('https://preview.pages.dev/sitemap.xml'), pageEnv)).text();
  assert.ok(xml.includes('https://vstupenky.online/events'));
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
  assert.ok(html.includes('<section class="catalog-archive"><h2>Proběhlé události</h2>'));
  assert.ok(html.includes('No date</a>'));
  assert.ok(html.includes('data-server-catalog="ready"'));
});


test('malformed catalogue payload is unavailable rather than an empty catalogue', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ error: 'unexpected payload' }));
  const html = await (await worker.fetch(request('/'), env)).text();
  assert.ok(html.includes('data-server-catalog="unavailable"'));
  assert.ok(!html.includes('Zatím zde nejsou žádné akce.'));
});


test('marketing root stays backend independent; catalog and legacy redirects preserve queries', async t => {
  t.mock.method(globalThis, 'fetch', async () => { throw new Error('backend down'); });
  const root = await productionWorker.fetch(request('/?utm_source=mail'), env);
  assert.equal(root.status, 200);
  assert.match(await root.text(), /Marketing/);
  assert.equal(fetch.mock.calls.length, 0);
  for (const [source, target] of [
    ['/?create=1&utm_source=mail', '/login?utm_source=mail'],
    ['/?q=ples', '/events?q=ples'], ['/events/?q=ples', '/events?q=ples'],
    ['/pro-poradatele?utm_source=mail', '/?utm_source=mail'],
    ['/prodej-vstupenek-na-ples?utm_source=mail','/?utm_source=mail'], ['/prodej-vstupenek-na-ples/','/'], ['/pro-poradatele/', '/'],
  ]) {
    const response = await productionWorker.fetch(request(source), env);
    assert.equal(response.status, 308);
    assert.equal(new URL(response.headers.get('location')).pathname + new URL(response.headers.get('location')).search, target);
  }
  const catalog = await productionWorker.fetch(request('/events'), env);
  assert.equal(catalog.status, 200);
  assert.match(await catalog.text(), /https:\/\/vstupenky.online\/events/);
});

test('marketing tenant keeps scanner, OAuth and internal document response policies', async () => {
  for (const path of ['/scan', '/scan/private-code', '/login-qr', '/google-auth', '/app/google-auth']) {
    const response = await productionWorker.fetch(request(path), env);
    assert.equal(response.status, 200, path);
    assert.equal(response.headers.get('cache-control'), 'no-store, no-transform', path);
    assert.equal(response.headers.get('referrer-policy'), 'no-referrer', path);
  }
  for (const path of ['/organizers-page', '/webclient', '/flutter']) {
    const response = await productionWorker.fetch(request(path), env);
    assert.equal(response.status, 301, path);
    assert.equal(new URL(response.headers.get('location')).pathname, '/');
  }
});


test('saved route identity redirects aliases with query intact and never confuses event/form namespaces', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    const args = JSON.parse(options.body);
    assert.equal(args.p_link_slug, 'old');
    return Response.json({ title: 'Occasion', form_title: 'Ticket form', form_link: args.p_route_type === 'form' ? 'new-form' : null, occasion_link: 'new-event' });
  });
  for (const [path, target] of [['/form/old?code=a%2Bb', '/form/new-form?code=a%2Bb'], ['/old/event?utm_source=old', '/new-event/event?utm_source=old']]) {
    const response = await worker.fetch(request(path), env);
    assert.equal(response.status, 308);
    assert.equal(response.headers.get('location'), 'https://tickets.invalid' + target);
  }
});

test('public event HTML contains factual escaped content without JS and removes its summary on Flutter readiness', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    assert.equal(JSON.parse(options.body).p_route_type, 'event');
    return Response.json({ title: 'Concert & friends', description: '<p>Doors &amp; music</p><script>bad()</script>', occasion_link: 'concert', start_time: '2027-02-20T18:00:00Z' });
  });
  const fixtureEnv = { ...env, ASSETS: { fetch: async () => new Response('<html><head><title>Old</title></head><body>Flutter</body></html>') } };
  const response = await worker.fetch(request('/concert/event'), fixtureEnv);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.ok(html.includes('<h1>Concert &amp; friends</h1>'));
  assert.ok(html.includes('Doors &amp; music'));
  assert.ok(html.includes('datetime="2027-02-20T18:00:00Z"'));
  assert.ok(!html.includes('flutter-first-frame')); // Cleanup belongs to the static CSP-bound Flutter bootstrap.
  assert.ok(!html.includes('bad()'));
  assert.ok(!html.includes('application/ld+json'));
});

test('HTTP errors, malformed payloads and missing backend configuration return temporary form failure', async t => {
  for (const result of [new Response('bad', {status:503}), Response.json([]), Response.json({error:'bad'})]) {
    t.mock.method(globalThis, 'fetch', async () => result.clone());
    assert.equal((await worker.fetch(request('/form/live'), env)).status, 503);
    t.mock.restoreAll();
  }
  assert.equal((await worker.fetch(request('/form/live'), {...env, SUPABASE_URL:null})).status, 503);
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
 assert.equal(response.headers.get('cache-control'),'no-store, no-transform');
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


test('unit catalogue uses the web shell and requests only its unit; admin routes keep Flutter', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    assert.deepEqual(JSON.parse(options.body), { p_organization_id: 3, p_unit_id: 2 });
    return Response.json({ occasions: [occasions[0]] });
  });
  for (const path of ['/unit/2', '/unit/2/']) {
    const response = await worker.fetch(request(path), env);
    const html = await response.text();
    assert.equal(response.status, 200);
    assert.ok(html.includes('id="event-search"'));
    assert.ok(html.includes('/form/camp-registration'));
    assert.ok(!html.includes('href="/program/event"'));
  }
  const admin = await worker.fetch(request('/unit/2/edit'), env);
  assert.equal(await admin.text(), 'flutter app');
});

test('unit catalogue exposes escaped organizer identity in HTML even without JavaScript', async t => {
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    assert.deepEqual(JSON.parse(options.body), { p_organization_id: 3, p_unit_id: 939 });
    return Response.json({ title: 'Pořadatel <script>bad</script>', occasions: [] });
  });
  const response = await worker.fetch(request('/unit/939'), env);
  const html = await response.text();
  assert.equal(response.status, 200);
  assert.ok(html.includes('<section id="unit-introduction" class="unit-introduction"><h1>Pořadatel &lt;script&gt;bad&lt;/script&gt;</h1>'));
  assert.ok(!html.includes('href="/pro-poradatele"'), 'individual organizer catalogues omit organizer navigation');
  assert.ok(html.includes('<title>Pořadatel &lt;script&gt;bad&lt;/script&gt; | vstupenky.online</title>'));
  assert.ok(!html.includes('<script>bad</script>'));
});


test('other tenants keep their event catalogue and never serve the marketing homepage', async t => {
 t.mock.method(globalThis,'fetch',async()=>Response.json({occasions}));
 const response=await worker.fetch(new Request('https://other.invalid/'),env);
 const html=await response.text();
 assert.equal(response.status,200);
 assert.ok(html.includes('data-server-catalog="ready"'));
 assert.ok(html.includes('/form/camp-registration'));
 assert.ok(!html.includes('data-page="organizers"'));
 assert.equal((await worker.fetch(new Request('https://other.invalid/pro-poradatele'),env)).status,404);
});

test('English catalog and sitemap keep each organization isolated across requests and outages', async t => {
  const source = workerSource.replace('const DEFAULT_LANGUAGE = "cs";', 'const DEFAULT_LANGUAGE = "en";').replace('const MARKETING = {enabled:false,pages:[],sitemapPaths:["/"]};', `const MARKETING = ${JSON.stringify(publicManifest(resolveContext(readConfig(new URL('../project.conf',import.meta.url)))))};`);
  const { default: english } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  t.mock.method(globalThis, 'fetch', async (_url, options) => {
    const org = JSON.parse(options.body).p_organization_id;
    if (org === 999) throw new Error('offline');
    return Response.json({ occasions: org === 900001 ? [] : [{ title: 'Czech catalog event',link: 'cs-event',features: [] }] });
  });
  await english.fetch(request('/events'), {...env, ORGANIZATION_ID: 3});
  const empty = await english.fetch(request('/events'), {...env, ORGANIZATION_ID: 900001});
  const html = await empty.text();
  assert.ok(html.includes('No events have been published yet.'));
  assert.ok(!html.includes('Czech catalog event'));
  const sitemap = await english.fetch(request('/sitemap.xml'), {...env, ORGANIZATION_ID: 900001});
  assert.ok(!(await sitemap.text()).includes('cs-event'));
  assert.match(sitemap.headers.get('cache-control'), /no-store/);
  const outage = await english.fetch(request('/events'), {...env, ORGANIZATION_ID: 999});
  const failure = await outage.text();
  assert.ok(failure.includes('Events could not be loaded.'));
  assert.ok(!failure.includes('Czech catalog event'));
});

test('registered marketing documents precede occasion redirects in ticketing-only production', async () => {
  const context=resolveContext(readConfig(new URL('../project.conf',import.meta.url)));
  const source=productionSource.replace('const IS_APP_SUPPORTED = true;', 'const IS_APP_SUPPORTED = false;')
    .replace('// PUBLIC_OCCASION_ROUTE_POLICY',readFileSync(new URL('../../web_client/src/services/public_occasion_routes.js',import.meta.url),'utf8').replaceAll('export function ','function '));
  const {default:ticketing}=await import('data:text/javascript;base64,'+Buffer.from(source).toString('base64'));
  const assets=new Map(context.pages.map(page=>[page.asset,`<title>${page.title}</title><link rel="canonical" href="${page.canonical}"><h1>${page.heading ?? 'Home'}</h1>`]));
  const fixture={ASSETS:{fetch:async request=>assets.has(new URL(request.url).pathname)?new Response(assets.get(new URL(request.url).pathname)):new Response('missing',{status:404})}};
  for(const page of context.pages.slice(1)) {
    const response=await ticketing.fetch(new Request(page.canonical+'?utm_source=guide'),fixture);
    assert.equal(response.status,200,page.path);
    assert.equal(response.headers.get('location'),null);
    const html=await response.text();assert.ok(html.includes(`<title>${page.title}</title>`));assert.ok(html.includes(`href="${page.canonical}"`));assert.ok(html.includes(page.heading));
    const slash=await ticketing.fetch(new Request(page.canonical+'/?utm_source=guide'),fixture);
    assert.equal(slash.status,308);assert.equal(slash.headers.get('location'),page.canonical+'?utm_source=guide');
  }
  assets.set('/organizers/ball-ticket-sales','retired guide still present in upstream asset cache');
  for(const path of ['/organizers','/organizers/ball-ticket-sales','/organizers/ball-ticket-sales?pwa-cache=1','/organizers/future-document','/organizers/seating-reservations']) {
    const response=await ticketing.fetch(new Request(context.origin+path),fixture);
    assert.equal(response.status,301);assert.equal(response.headers.get('location'),context.origin+'/');
  }
  for (const path of ['/prodej-vstupenek-na-ples','/prodej-vstupenek-na-ples/']) {
    const response=await ticketing.fetch(new Request(context.origin+path+'?utm_source=old'),fixture);
    assert.equal(response.status,308);assert.equal(response.headers.get('location'),context.origin+'/?utm_source=old');
  }
  const legacy=await ticketing.fetch(new Request(context.origin+'/legacy-occasion/event'),fixture);
  assert.equal(legacy.status,302);assert.equal(legacy.headers.get('location'),context.origin+'/');
});
