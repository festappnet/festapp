import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const script = readFileSync(new URL('../cloudflare_build.sh', import.meta.url), 'utf8');
const source = script.match(/<<'WORKER'\n([\s\S]*?)\nWORKER/)[1];
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
    ['/', '/webclient'], ['/form/', '/webclient'], ['/form/example', '/webclient'],
    ['/login', '/flutter'], ['/auth_bridge', '/auth_bridge'], ['/unknown', '/unknown'],
    ['/web-assets/app.js', '/web-assets/app.js'], ['/main.dart.js', '/main.dart.js'],
  ]) {
    const response = await worker.fetch(new Request(origin + path), env);
    assertPolicy(response);
    assert.equal(response.status, 200);
    assert.equal(await response.text(), body);
    if (path === '/main.dart.js') assert.equal(response.headers.get('cache-control'), 'no-cache, must-revalidate');
  }
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
