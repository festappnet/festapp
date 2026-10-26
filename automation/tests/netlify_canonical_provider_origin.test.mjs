import assert from 'node:assert/strict';
import test from 'node:test';

import handler from '../../netlify/edge-functions/canonical-provider-origin.js';

const nextResponse = new Response('next', { status: 200 });
const context = { next: () => nextResponse };

test('redirects only the registered Netlify provider hostname', async () => {
  const response = await handler(
    new Request('https://festivalslunovrat.netlify.app/program?day=1'),
    context,
  );
  assert.equal(response.status, 301);
  assert.equal(response.headers.get('location'), 'https://app.festivalslunovrat.cz/program?day=1');

  assert.equal(await handler(
    new Request('https://app.festivalslunovrat.cz/program?day=1'),
    context,
  ), nextResponse);
});

test('serves the retirement worker on legacy worker boundaries', async () => {
  for (const path of ['/festapp_service_worker.js', '/flutter_service_worker.js', '/push/OneSignalSDKWorker.js']) {
    let forwarded;
    const response = await handler(
      new Request(`https://festivalslunovrat.netlify.app${path}?cache=stale`),
      { next: (request) => { forwarded = request; return nextResponse; } },
    );
    assert.equal(response, nextResponse);
    assert.equal(forwarded.url, 'https://festivalslunovrat.netlify.app/netlify-retire-worker.js');
  }
});
