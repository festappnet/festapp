import { test } from 'node:test';
import assert from 'node:assert/strict';
import { imageClientConfig, verifyImageClient } from '../verify_image_service.mjs';

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
