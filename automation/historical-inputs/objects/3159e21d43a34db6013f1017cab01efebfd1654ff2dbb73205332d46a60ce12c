import { overviewRequiredLinks } from "./emailActionLink.ts";
import { completeEmailContent } from "./emailContentCompletion.ts";
import { renderEmail } from './emailDelivery.ts';
import assert from 'node:assert/strict';
import { orderEmailOverviewUrl } from './orderEmailOverview.ts';
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
    email.html = completeEmailContent(email.html, overviewRequiredLinks(first));
    email.html = completeEmailContent(email.html, overviewRequiredLinks(first));
    assert.equal(email.html, '<html><body>Confirmation</body></html>');
    assert.equal(await orderEmailOverviewUrl(row, async () => null), null);
  } finally {
    if (previous === undefined) Deno.env.delete('EMAIL_PAYLOAD_KEY'); else Deno.env.set('EMAIL_PAYLOAD_KEY', previous);
  }
});

Deno.test('status link belongs inside the order card, before the signature, exactly once', () => {
 const card=generateFullOrder({email:'customer@example.invalid',phone:'+420 731 140 198'},[],[],'cs','5W8H2U8I9W');
 const email={from:'',to:'',subject:'',html:`<html><head></head><body>${card}<p>Signature</p></body></html>`,replyTo:'',attachments:[]};
 const url='https://tickets.example.invalid/order?order_id=1&token='+ 'a'.repeat(64);
 email.html = completeEmailContent(email.html, overviewRequiredLinks(url));email.html = completeEmailContent(email.html, overviewRequiredLinks(url));
 assert.equal((email.html.match(/href=/g)||[]).length,1);
 assert.ok(email.html.indexOf('Zobrazit aktuální stav objednávky')<email.html.indexOf('Signature'));
 assert.match(email.html,/platby a historii změn/);
 assert.doesNotMatch(email.html,/mailto:|tel:|&#8203;|customer-order-overview-link/);
 assert.match(email.html,/customer@example.invalid/);
 assert.ok(card.includes('+420 731 140 198'));
});
Deno.test('custom links are not duplicated and English status copy is explicit', () => {
 const url='https://tickets.example.invalid/order?order_id=1&token='+ 'a'.repeat(64);
 const make=(html:string)=>({from:'',to:'',subject:'',html,replyTo:'',attachments:[]});
 const custom=make('<a href="'+url.replaceAll('&','&amp;')+'">My overview</a>');
 custom.html = completeEmailContent(custom.html, overviewRequiredLinks(url));assert.equal((custom.html.match(/href=/g)||[]).length,1);
 const english=make(generateFullOrder({},[],[],'en'));
 english.html = completeEmailContent(english.html, overviewRequiredLinks(url, 'en'));assert.match(english.html,/View current order status/);
 const noLink=make(generateFullOrder({},[],[]));noLink.html = completeEmailContent(noLink.html, overviewRequiredLinks(null));
 assert.doesNotMatch(noLink.html,/href=|customer-order-overview-link/);
});

Deno.test('template substitution preserves text values, subjects and authored links without linkification', async()=>{
 const values={account:'2502719268/2010',phone:'+420 731 140 198',email:'user@example.invalid',url:'https://example.invalid/order?token=abc'};
 const email=await renderEmail({to:'test@example.invalid',context:{organization:1},substitutions:values},async()=>({template:{id:1,subject:'{{account}} {{phone}}',html:'<p>{{account}} {{phone}} {{email}}</p><a href="{{url}}">Status</a>'}}));
 assert.equal(email.subject,'2502719268/2010 +420 731 140 198');
 assert.equal(email.html.replace(/<style[\s\S]*?<\/style>/g,'').replace(/<span class="festapp-plain-value">([^<]*)<\/span>/g,'$1'),'<p>2502719268/2010 +420 731 140 198 user@example.invalid</p><a href="https://example.invalid/order?token=abc">Status</a>');
 assert.doesNotMatch(email.html,/mailto:|tel:|&#8203;/);
});
