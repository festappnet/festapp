import assert from 'node:assert/strict';
import { orderEmailOverviewUrl, includeOrderOverview } from './orderEmailOverview.ts';
import { generateFullOrder } from './orderOverview.ts';
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
    assert.match(email.html, /<\/a><\/div><\/body>/);
    assert.equal(await orderEmailOverviewUrl(row, async () => null), null);
  } finally {
    if (previous === undefined) Deno.env.delete('EMAIL_PAYLOAD_KEY'); else Deno.env.set('EMAIL_PAYLOAD_KEY', previous);
  }
});

Deno.test('status link belongs inside the order card, before the signature, exactly once', () => {
 const card=generateFullOrder({email:'customer@example.invalid',phone:'+420 731 140 198'},[],[],'cs','5W8H2U8I9W');
 const email={from:'',to:'',subject:'',html:`<html><head></head><body>${card}<p>Signature</p></body></html>`,replyTo:'',attachments:[]};
 const url='https://tickets.example.invalid/order?order_id=1&token='+ 'a'.repeat(64);
 includeOrderOverview(email,url);includeOrderOverview(email,url);
 assert.equal((email.html.match(/href=/g)||[]).length,1);
 assert.ok(email.html.indexOf('Zobrazit aktuální stav objednávky')<email.html.indexOf('Signature'));
 assert.match(email.html,/platby a historii změn/);
 assert.match(email.html,/format-detection.*telephone=no,email=no/);
 assert.doesNotMatch(email.html,/mailto:|tel:|customer@example.invalid|731 140 198|customer-order-overview-link/);
 assert.match(email.html,/customer&#8203;@&#8203;example/);
 assert.equal(card.replaceAll('&#8203;','').includes('+420 731 140 198'),true);
});
Deno.test('custom links are not duplicated and English status copy is explicit', () => {
 const url='https://tickets.example.invalid/order?order_id=1&token='+ 'a'.repeat(64);
 const make=(html:string)=>({from:'',to:'',subject:'',html,replyTo:'',attachments:[]});
 const custom=make('<a href="'+url.replaceAll('&','&amp;')+'">My overview</a>');
 includeOrderOverview(custom,url);assert.equal((custom.html.match(/href=/g)||[]).length,1);
 const english=make(generateFullOrder({},[],[],'en'));
 includeOrderOverview(english,url,'en');assert.match(english.html,/View current order status/);
 const noLink=make(generateFullOrder({},[],[]));includeOrderOverview(noLink,null);
 assert.doesNotMatch(noLink.html,/href=|customer-order-overview-link/);
});
