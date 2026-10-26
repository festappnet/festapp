import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { createTransactionFetchHandler } from './handler.ts';
const request = (body: unknown, token = true) => new Request('https://fixture.invalid/fetch-transactions', {
  method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer fixture' } : {}) }, body: JSON.stringify(body),
});
Deno.test('transaction fetch forwards SQL-authorized connections exactly once without a second permission request', async () => {
  const calls: unknown[] = [];
  const rows = [{ connection_id: 7, remote_bank_account_id: '123' }];
  const handler = createTransactionFetchHandler({
    connections(token, link) { calls.push({ token, link }); return Promise.resolve(rows); },
    synchronize(connections) { calls.push(connections); return Promise.resolve([{ connection_id: '7' }]); },
  });
  const response = await handler(request({ occasionLink: 'owned' }));
  assertEquals(response.status, 200);
  assertEquals(await response.json(), { results: [{ connection_id: '7' }] });
  assertEquals(calls, [{ token: 'Bearer fixture', link: 'owned' }, rows]);
});
Deno.test('transaction fetch never calls the remote synchronizer after revoked SQL authorization', async () => {
  let remoteCalls = 0;
  const handler = createTransactionFetchHandler({
    connections() { throw new Error('BANK_SYNC_FORBIDDEN'); },
    synchronize() { remoteCalls++; return Promise.resolve([]); },
  });
  const response = await handler(request({ occasionLink: 'owned' }));
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: 'bank_account_admin_required' });
  assertEquals(remoteCalls, 0);
});
Deno.test('transaction fetch rejects unauthenticated and malformed requests before any SQL or remote work', async () => {
  let calls = 0;
  const handler = createTransactionFetchHandler({
    connections() { calls++; return Promise.resolve([]); },
    synchronize() { calls++; return Promise.resolve([]); },
  });
  assertEquals((await handler(request({ occasionLink: 'owned' }, false))).status, 401);
  assertEquals((await handler(request({ occasionLink: 7 }))).status, 400);
  assertEquals((await handler(request({ occasionLink: ' ' }))).status, 400);
  assertEquals(calls, 0);
});
