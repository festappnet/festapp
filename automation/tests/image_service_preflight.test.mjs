import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { imageClientConfig, verifyImageClient, verifyWalletEmailArtwork } from '../verify_image_service.mjs';

const client = imageClientConfig('WEB_LINK=https://slunovrat.festapp.net\nIMAGE_API_URL=https://image-api.festapp.net\nIMAGE_PROJECT_ID=slunovrat\nBACKEND_ACTIVATION_TENANT_ID=festivalslunovrat\n');
const cors = {
  'Access-Control-Allow-Origin': client.origin,
  'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
  'Access-Control-Allow-Headers': 'Authorization, Content-Type',
};

test('the production probe requires both preflight and a recognized project, without a real token', async () => {
  let calls = 0;
  await verifyImageClient(client, async (_, options) => {
    calls++;
    if (options.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    assert.equal(options.headers.Authorization, 'Bearer diagnostic-invalid-token');
    assert.equal(options.body.get('projectId'), 'slunovrat');
    assert.equal(options.body.get('file').size, 0);
    return Response.json({ error: { code: 'FORBIDDEN' } }, { status: 403, headers: cors });
  });
  assert.equal(calls, 2);
});

test('a denied upload origin fails before the multipart probe', async () => {
  let calls = 0;
  await assert.rejects(verifyImageClient(client, async () => {
    calls++;
    return new Response(null, { status: 403 });
  }), /preflight rejected/);
  assert.equal(calls, 1);
});

test('a permitted origin cannot hide UNKNOWN_PROJECT', async () => {
  await assert.rejects(verifyImageClient(client, async (_, options) => {
    if (options.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    return Response.json({ error: { code: 'UNKNOWN_PROJECT' } }, { status: 400, headers: cors });
  }), /UNKNOWN_PROJECT/);
});

test('a generic success or missing CORS on the upload response is not accepted', async () => {
  for (const response of [Response.json({}, { headers: cors }), Response.json({ error: { code: 'FORBIDDEN' } }, { status: 403 })]) {
    await assert.rejects(verifyImageClient(client, async (_, options) => options.method === 'OPTIONS'
      ? new Response(null, { status: 204, headers: cors }) : response), /authorization boundary/);
  }
});

test('email badge readiness rejects the missing public Apple image seen by email clients', async () => {
  await assert.rejects(verifyWalletEmailArtwork(async () => new Response('Not found', { status: 404 })), /Wallet email artwork unavailable/);
});

test('email badge readiness verifies the exact PNG bytes for every configured locale and provider', async () => {
  const requested = [];
  const count = await verifyWalletEmailArtwork(async url => {
    requested.push(url);
    const [,provider,, ,locale] = new URL(url).pathname.split('/').slice(1);
    const directory = provider === 'apple-wallet' ? 'email' : 'condensed';
    return new Response(fs.readFileSync(`assets/brand/${provider}/${directory}/${locale}`), {headers:{'Content-Type':'image/png'}});
  });
  assert.equal(count,12);
  assert.equal(new Set(requested).size,12);
});

test('a successful HTML page or changed PNG cannot satisfy email artwork readiness', async () => {
  await assert.rejects(verifyWalletEmailArtwork(async () => new Response('SPA fallback', { headers:{'Content-Type':'text/html'} })), /artwork unavailable/);
  await assert.rejects(verifyWalletEmailArtwork(async () => new Response('wrong bytes', { headers:{'Content-Type':'image/png'} })), /differs from canonical/);
});
