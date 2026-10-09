import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { getOccasionHref } from '../../web_client/src/components/occasion/occasion_link.js';

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const workerSource = script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]
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
