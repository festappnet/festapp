import assert from 'node:assert/strict';
import test from 'node:test';
import fs from 'node:fs';
import worker from './index.mjs';
test('retired public, signed and transformed paths terminate without origin or cache reads', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = () => { throw new Error('Retirement must never fetch an origin'); };
  try {
    for (const path of ['/storage/v1', '/storage/v1/object/public/files/x.jpg', '/storage/v1/object/sign/files/x?token=old', '/storage/v1/render/image/public/files/x?w=200']) {
      const response = await worker.fetch(new Request('https://api.festapp.net' + path));
      assert.equal(response.status, 410);
      assert.equal(response.headers.get('cache-control'), 'no-store');
      assert.equal(response.headers.has('location'), false);
    }
  } finally { globalThis.fetch = original; }
});
test('other hosts and live API paths are outside the handler contract', async () => {
  for (const url of ['https://api.festapp.net/auth/v1/health', 'https://api.festapp.net/rest/v1/', 'https://akh.img.festapp.net/storage/v1/file', 'https://img.festapp.net/images/x']) {
    assert.equal((await worker.fetch(new Request(url))).status, 404);
  }
});
test('deployed routes cover only canonical retired paths and need no bindings or secrets', () => {
  const config = JSON.parse(fs.readFileSync(new URL('./wrangler.json', import.meta.url)));
  assert.deepEqual(config.routes.map(r => r.pattern), ['api.festapp.net/storage/v1', 'api.festapp.net/storage/v1/*']);
  assert.equal(config.workers_dev, false);
  assert.equal(config.preview_urls, false);
  assert.equal(config.r2_buckets, undefined);
  assert.equal(config.services, undefined);
});
