import assert from 'node:assert/strict';
import { orderEmailOverviewUrl, includeOrderOverview } from './orderEmailOverview.ts';
import { prepareOrderOverviewSource } from './waitlistEmail.ts';
Deno.test('confirmation and subsequent emails reuse the root token, including split orders', async () => {
  const previous = Deno.env.get('EMAIL_PAYLOAD_KEY');
  Deno.env.set('EMAIL_PAYLOAD_KEY', btoa(String.fromCharCode(...new Uint8Array(32).fill(19))));
  try {
    const context = { orderId: 12, recipient: 'test@example.invalid', organization: 1, occasion: 2, unit: 3,
      occasionTitle: 'Synthetic', participantCount: 2, formLink: 'test', webLink: 'https://tenant.example.invalid/' };
    let source: Awaited<ReturnType<typeof prepareOrderOverviewSource>> | null = null;
    let writes = 0;
    const rpc = async (_name: string, params: Record<string, unknown>) => {
      if (params.p_delivery) { source ||= params.p_delivery as Awaited<ReturnType<typeof prepareOrderOverviewSource>>; writes++; }
      return { ...context, source };
    };
    const row = { order_id: 12, recipient: context.recipient, message_id: crypto.randomUUID() };
    const first = await orderEmailOverviewUrl(row, rpc);
    assert.match(first!, /\?order_id=12&token=[a-f0-9]{64}$/);
    for (const order_id of [12, 13, 12]) {
      assert.equal(await orderEmailOverviewUrl({ ...row, order_id, message_id: crypto.randomUUID() }, rpc), first);
    }
    assert.equal(writes, 1);
    const email = { from: '', to: '', subject: '', html: '<html><body>Confirmation</body></html>', replyTo: '', attachments: [] };
    includeOrderOverview(email, first);
    includeOrderOverview(email, first);
    assert.equal((email.html.match(/<a /g) || []).length, 1);
    assert.match(email.html, /order_id=12&amp;token=/);
    assert.match(email.html, /<\/a><\/p><\/body>/);
    assert.equal(await orderEmailOverviewUrl(row, async () => null), null);
  } finally {
    if (previous === undefined) Deno.env.delete('EMAIL_PAYLOAD_KEY'); else Deno.env.set('EMAIL_PAYLOAD_KEY', previous);
  }
});
