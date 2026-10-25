import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const bootstrap = readFileSync(new URL('../../web_client/public/public-web-analytics.js', import.meta.url), 'utf8');
const token = 'a'.repeat(32);
function browser(path = '/', overrides = {}) {
  const added = [], navigation = [], history = [];
  const location = new URL('https://tenant.invalid' + path);
  location.assign = url => navigation.push(['assign', url]);
  location.replace = url => navigation.push(['replace', url]);
  const window = { location, history: {
    pushState: (...args) => history.push(['push', ...args]),
    replaceState: (...args) => history.push(['replace', ...args]),
  } };
  window.self = window.top = window;
  const navigator = {};
  const document = {
    currentScript: { dataset: { analyticsHost: location.hostname, analyticsToken: token } },
    referrer: '', head: { appendChild: script => added.push(script) },
    createElement: () => ({ dataset: {} }),
  };
  Object.defineProperty(document, 'cookie', { get() { throw Error('No analytics cookies'); }, set() { throw Error('No analytics cookies'); } });
  Object.assign(document, overrides.document);
  Object.assign(navigator, overrides.navigator);
  if (overrides.embed) window.top = {};
  vm.runInNewContext(bootstrap, { window, document, navigator, URL });
  return { added, navigation, history, window };
}

test('public pages load one manual beacon without SPA tracking or persistent storage', () => {
  for (const path of ['/', '/events', '/unit/12', '/form/public', '/form/public?utm_source=google']) {
    const result = browser(path);
    assert.equal(result.added.length, 1, path);
    assert.deepEqual(JSON.parse(result.added[0].dataset.cfBeacon), { token, spa: false });
    assert.equal(result.added[0].referrerPolicy, 'origin');
  }
});

test('private capabilities, legacy routes, previews and embeds never load a beacon', () => {
  for (const path of ['/scan/SECRET', '/order', '/google-auth', '/admin', '/unit/12/edit',
    '/event/event', '/form/public/stripe/pay', '/form/public#order?token=SECRET',
    '/#/scan/SECRET', '/form/public?preview=1', '/form/public?token=SECRET', '/form/public?embed=1']) {
    assert.equal(browser(path).added.length, 0, path);
  }
  for (const overrides of [{ embed: true }, { document: { referrer: 'https://tenant.invalid/scan/SECRET' } },
    { document: { referrer: 'https://outside.invalid/private/SECRET' } }]) {
    assert.equal(browser('/', overrides).added.length, 0);
  }
  assert.equal(browser('/', { document: { referrer: 'https://www.google.com/' } }).added.length, 1);
  assert.equal(browser('/', { navigator: { doNotTrack: '1', globalPrivacyControl: true } }).added.length, 1);
});

test('public-to-private and public-to-public history changes leave the measured document before its path can change', () => {
  const result = browser('/form/public');
  result.window.history.pushState({}, '', '/scan/SECRET');
  result.window.history.replaceState({}, '', '/form/other');
  assert.deepEqual(result.navigation, [['assign', 'https://tenant.invalid/scan/SECRET'], ['replace', 'https://tenant.invalid/form/other']]);
  assert.equal(result.window.location.pathname, '/form/public');
  assert.equal(result.history.length, 0);
  result.window.history.pushState({}, '', '#order?token=SECRET');
  assert.equal(result.history.length, 1, 'same-path checkout overlays keep their history behavior');
});

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const shared = file => readFileSync(new URL('../../web_client/src/' + file, import.meta.url), 'utf8').replaceAll('export function', 'function');
const source = shared('services/scanner_routes.js') + '\n' + script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1]
  .replace('// SHARED_PUBLIC_PAGE_SEO', shared('services/public_page_seo.js'))
  .replace('// SHARED_CATALOG_CLASSIFICATION', shared('components/occasion/catalog.js'))
  .replace('const CANONICAL_ORIGIN = null;', 'const CANONICAL_ORIGIN = "https://tenant.invalid";')
  .replace('const PUBLIC_WEB_ANALYTICS = null;', `const PUBLIC_WEB_ANALYTICS = ${JSON.stringify({ token })};`);
const { default: worker } = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
const env = {
  SUPABASE_URL: 'https://backend.invalid', SUPABASE_ANON_KEY: 'fixture', ORGANIZATION_ID: 1,
  ASSETS: { fetch: async () => new Response('<!doctype html><html><head></head><body>app</body></html>', { headers: { 'content-type': 'text/html' } }) },
};
test('Pages owns public-only injection and suppresses automatic injection on every HTML route', async t => {
  t.mock.method(globalThis, 'fetch', async () => Response.json({ title: 'Public', form_link: 'public', occasions: [] }));
  for (const [path, measured] of [['/', true], ['/form/public', true], ['/scan/SECRET', false],
    ['/admin', false], ['/unit/1/edit', false], ['/google-auth', false], ['/order', false],
    ['/public/event', false], ['/webclient?pwa-cache=1', false], ['/privacy/', false]]) {
    const response = await worker.fetch(new Request('https://tenant.invalid' + path), env);
    const html = await response.text();
    assert.equal(html.includes('data-analytics-token='), measured, path);
    assert.match(response.headers.get('cache-control'), /no-transform/, path);
    assert.ok(!html.includes('data-cf-beacon'), 'shared document cannot contain an unconditional beacon');
  }
});
