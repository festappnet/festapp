import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync, mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import vm from 'node:vm';
import { isPublicOccasionAppPath, unsupportedOccasionAppRedirect } from '../../web_client/src/services/public_occasion_routes.js';

const disabled = [
  '/demo', '/demo/', '/demo/news', '/demo/newsForm', '/demo/event',
  '/demo/event/42', '/demo/map', '/demo/map/42', '/demo/user', '/demo/info/42',
  '/demo/unit', '/demo/timetable', '/demo/myschedule', '/demo/counseling',
  '/demo/game', '/demo/songbook', '/demo/userstay', '/demo/%65vent/42',
  '/unit-ball/event', '/demo/eventEdit/42', '/demo/reception', '/demo/cleaning/1', '/map-editor',
];
const preserved = [
  '/', '/form/demo', '/form/event', '/login', '/unit/2/edit', '/admin',
  '/demo/reservations/orders/current',
  '/demo/check/42',
  '/google-auth', '/app/google-auth', '/resetPassword',
  '/privacy/', '/support/', '/auth_bridge.html', '/main.dart.js',
  '/assets/translations/cs.json', '/canvaskit/chromium/canvaskit.wasm',
];
const oldAdministration = ['/demo/admin', '/demo/admin/info/information', '/demo/admin/volunteers', '/demo/admin/events/schedule'];
const redirected = [...disabled.map(path => [path, '/']), ...oldAdministration.map(path => [path, '/demo/reservations'])];
const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const template = script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1];
const stamp = script.match(/python3 - build\/web\/_worker\.js automation\/project\.conf <<'PY'\n([\s\S]*?)\nPY/)[1];
const projectRoot = new URL('../../', import.meta.url).pathname;

async function workerFor(supported, dir) {
  const file = path.join(dir, 'worker.js');
  const config = path.join(dir, 'project.conf');
  writeFileSync(file, template);
  writeFileSync(config, `IS_APP_SUPPORTED=${supported}\nFORCE_OCCASION_LINK=\nAPP_NAME=Fixture\n`);
  const stamped = spawnSync('python3', ['-', file, config], {
    input: stamp, encoding: 'utf8', cwd: projectRoot,
  });
  assert.equal(stamped.status, 0, stamped.stderr);
  return (await import('data:text/javascript;base64,' + Buffer.from(readFileSync(file)).toString('base64'))).default;
}

const assets = { fetch: async request => {
  const pathname = new URL(request.url).pathname;
  return ['/flutter', '/webclient'].includes(pathname)
    ? new Response(pathname) : new Response('missing', { status: 404 });
} };

test('public path policy separates occasion screens from ticketing and account flows', () => {
  assert.equal(isPublicOccasionAppPath('/demo/event'), true);
  for (const pathname of oldAdministration) assert.equal(unsupportedOccasionAppRedirect(pathname), '/demo/reservations', pathname);
  for (const pathname of disabled) assert.equal(unsupportedOccasionAppRedirect(pathname), '/', pathname);
  for (const pathname of preserved) assert.equal(unsupportedOccasionAppRedirect(pathname), null, pathname);
});

test('stamped hosting worker redirects disabled screens before loading Flutter', async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'festapp-public-scope-'));
  try {
    const worker = await workerFor(false, dir);
    for (const [pathname, destination] of redirected) {
      let fetched = false;
      const response = await worker.fetch(new Request('https://fixture.invalid' + pathname), {
        ASSETS: { fetch: async () => { fetched = true; throw Error('must not load Flutter'); } },
      });
      assert.equal(response.status, 302, pathname);
      assert.equal(response.headers.get('location'), 'https://fixture.invalid' + destination);
      assert.equal(response.headers.get('x-content-type-options'), 'nosniff');
      assert.equal(fetched, false);
    }
    for (const pathname of preserved.filter(p => !p.includes('.js') && !p.includes('.wasm') && !p.includes('.json'))) {
      const response = await worker.fetch(new Request('https://fixture.invalid' + pathname), { ASSETS: assets });
      assert.notEqual(response.status, 302, pathname);
    }
    const supported = await workerFor(true, dir);
    for (const pathname of ['/demo/event', '/demo/admin/info/information']) {
      const response = await supported.fetch(new Request('https://fixture.invalid' + pathname), { ASSETS: assets });
      assert.equal(response.status, 200, pathname);
      assert.equal(await response.text(), '/flutter');
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('disabled PWA redirects public navigation offline before reading any cached Flutter shell', async () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'festapp-pwa-public-scope-'));
  try {
    for (const file of ['flutter', 'webclient', 'main.dart.js']) writeFileSync(path.join(dir, file), file);
    const generated = spawnSync(process.execPath, ['automation/generate_pwa_service_worker.mjs', dir, '1.2.3+4', 'demo', 'false'], { cwd: projectRoot, encoding: 'utf8' });
    assert.equal(generated.status, 0, generated.stderr);
    const source = readFileSync(path.join(dir, 'festapp_service_worker.js'), 'utf8');
    assert.match(source, /const IS_APP_SUPPORTED = false;/);
    assert.match(source, /const FORCED_OCCASION_PATH = null;/);
    const handlers = {};
    const context = vm.createContext({ URL, Request, Response, Headers, Promise, setTimeout, clearTimeout, console,
      caches: { open: () => { throw Error('must not use cached Flutter shell'); } },
      fetch: () => { throw Error('offline'); },
      self: { location: { origin: 'https://fixture.invalid' }, addEventListener: (name, fn) => { handlers[name] = fn; } },
    });
    vm.runInContext(source, context);
    for (const [pathname, destination] of redirected) {
      const request = new Request('https://fixture.invalid' + pathname);
      Object.defineProperty(request, 'mode', { value: 'navigate' });
      let response;
      handlers.fetch({ request, respondWith: value => { response = value; }, waitUntil: () => {} });
      response = await response;
      assert.equal(response.status, 302, pathname);
      assert.equal(response.headers.get('location'), 'https://fixture.invalid' + destination);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('ticket-only catalog and sitemap do not advertise public app URLs', async t => {
  const dir = mkdtempSync(path.join(tmpdir(), 'festapp-public-catalog-scope-'));
  t.mock.method(globalThis, 'fetch', async () => Response.json({ occasions: [
    { title: 'Public program', link: 'program-only', features: [] },
    { title: 'Tickets', link: 'ticket-event', form: { link: 'buy-tickets' },
      features: [{ code: 'form', is_enabled: true }] },
  ] }));
  try {
    const worker = await workerFor(false, dir);
    const env = {
      SUPABASE_URL: 'https://backend.invalid', SUPABASE_ANON_KEY: 'public-fixture',
      ASSETS: { fetch: async () => new Response('<div id="events-grid"></div>') },
    };
    for (const pathname of ['/', '/sitemap.xml']) {
      const response = await worker.fetch(new Request('https://fixture.invalid' + pathname), env);
      const body = await response.text();
      assert.ok(body.includes('/form/buy-tickets'), pathname);
      assert.ok(!body.includes('/program-only/event'), pathname);
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('web client does not initialize Flutter for unsupported public links', async t => {
  const previousWindow = globalThis.window;
  const replaced = [];
  globalThis.window = { location: { origin: 'https://fixture.invalid', pathname: '/demo/event', href: 'https://fixture.invalid/demo/event', hash: '' }, history: { replaceState: (_state, _title, target) => replaced.push(target) } };
  const { RouterService } = await import('../../web_client/src/services/router_service.js');
  const { AppConfig } = await import('../../web_client/src/app_config.js');
  const previousSupported = AppConfig.isAppSupported;
  const opened = [];
  t.mock.method(RouterService, 'openExternalUrl', target => opened.push(target));
  try {
    AppConfig.isAppSupported = false;
    assert.equal(await RouterService.handleInitialLoad(), true);
    assert.deepEqual(replaced, ['/']);
    assert.equal(RouterService.getOccasionAppPath('demo'), '/');
    await RouterService.navigateToOccasionApp('demo');
    await RouterService.navigateToFlutterRoute('/demo/map/42');
    assert.deepEqual(opened, ['/', '/']);
  } finally {
    AppConfig.isAppSupported = previousSupported;
    globalThis.window = previousWindow;
  }
});
