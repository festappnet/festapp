import assert from "node:assert/strict";
import { completeEmailContent } from "./emailContentCompletion.ts";
import {
  overviewEmailSubstitutions,
  overviewRequiredLinks,
  waitlistActionLink,
} from "./emailActionLink.ts";
Deno.test("pure completion matches generated shared fixtures and is idempotent", async () => {
  const asset = JSON.parse(
    await Deno.readTextFile(
      new URL(
        "../../../assets/email_templates/preview_examples.json",
        import.meta.url,
      ),
    ),
  );
  for (const fixture of asset.compositionFixtures) {
    const result = completeEmailContent(fixture.html, fixture.requiredLinks, fixture.wrapperHtml);
    assert.equal(result, fixture.expected, fixture.name);
    assert.equal(completeEmailContent(result, fixture.requiredLinks), result);
  }
});
Deno.test("action HTML preserves separate producer styles and escaping", () => {
  const url = 'https://example.invalid/order?a=1&b="<value>';
  const values = overviewEmailSubstitutions(url);
  assert.match(values.order_overview_button, /padding:12px 18px/);
  assert.match(values.order_overview_button, /&amp;b=&quot;&lt;value&gt;/);
  assert.match(waitlistActionLink("encoded-url", "Label"), /padding:12px 20px/);
  assert.equal(overviewEmailSubstitutions(null).order_overview_button, "");
  assert.deepEqual(overviewRequiredLinks(null), []);
});
Deno.test('payment action occupies one body or wrapper slot and legacy aliases cannot duplicate it', () => {
  const action='<p><a href="https://tickets.example/pay#pay=private">Continue payment</a></p>';
  for (const [body,wrapper] of [
    ['<!--festapp-payment-action--><!--festapp-payment-action-->','<div>{{content}}</div>'],
    ['<!--festapp-payment-action-->','<div>{{content}}{{paymentAction}}</div>'],
    [action,'<div>{{content}}{{paymentAction}}</div>'],
  ]) {
    const html=completeEmailContent(body,[],wrapper,action);
    assert.equal(html.split('Continue payment').length-1,1);
    assert.equal(html.includes('festapp-payment-action'),false);
    assert.equal(html.includes('{{paymentAction}}'),false);
  }
  assert.equal(completeEmailContent('{{paymentAction}}',[],null,''),'');
});
