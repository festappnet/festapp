import assert from "node:assert/strict";
import { emailVariableContract } from "./emailVariables.ts";
import { renderEmail } from "./emailDelivery.ts";
import { orderIdentityValues } from "./emailCommunication.ts";
import cases from "../../../packages/festapp_contracts/email-composition-cases.json" with {
  type: "json",
};
import { generateFullOrder } from "./orderOverview.ts";

Deno.test("identity producers expose only the canonical variables", () => {
  assert.deepEqual(orderIdentityValues("Slavnost", "ABC123"), {
    occasionTitle: "Slavnost",
    orderSymbol: "ABC123",
  });
  assert.equal(Object.hasOwn(emailVariableContract, "aliases"), false);
});

for (const part of ["subject", "html", "wrapper"]) {
  Deno.test(`retired placeholders cannot enter email preparation through ${part}`, async () => {
    await assert.rejects(
      renderEmail({
        to: "preview@example.invalid",
        templateCode: "TICKET_ORDER_CONFIRMATION",
        context: { organization: 1 },
        substitutions: { orderSymbol: "ABC123", occasionTitle: "Slavnost" },
      }, async () => ({
        template: {
          id: 1,
          subject: part === "subject" ? "{{order_symbol}}" : "Test",
          html: part === "html"
            ? "{{ occasion_title }}"
            : "<p>{{orderSymbol}}</p>",
        },
        wrapper: {
          html: part === "wrapper"
            ? "<main>{{occasion_title}} {{content}}</main>"
            : "<main>{{content}}</main>",
        },
      })),
      /noncanonical_email_template/,
    );
  });
}

Deno.test("retired-looking customer data remains literal and never becomes a template", async () => {
  const prepared = await renderEmail(
    {
      to: "preview@example.invalid",
      templateCode: "TICKET_ORDER_CONFIRMATION",
      context: { organization: 1 },
      substitutions: { occasionTitle: "{{order_symbol}}" },
    },
    async () => ({
      template: {
        id: 1,
        subject: "{{occasionTitle}}",
        html: "<p>{{occasionTitle}}</p>",
      },
    }),
  );
  assert.equal(prepared.subject, "{{order_symbol}}");
  assert.equal(prepared.html, "<p>{{order_symbol}}</p>");
});

Deno.test("the shared overview escapes raw identity, contact, note and product fields once", () => {
  const html = generateFullOrder(
    {
      name: "Jan & <img src=x>",
      surname: "Novák",
      email: "jan@example.invalid",
      note: "<script>note</script>",
    },
    [{
      ticket_symbol: "ABC<svg>",
      note: "<img src=x>",
      products: [{
        title: "<script>product</script>",
        price: 100,
        currency_code: "CZK",
      }],
    }],
    [],
    "cs",
    "ORDER<img>",
  );
  assert.doesNotMatch(html, /<img|<svg|<script/);
  assert.match(html, /Jan &amp; &lt;img/);
  assert.doesNotMatch(html, /&amp;amp;/);
});

for (const c of cases) {
  Deno.test(`shared delivery/preview composition: ${c.name}`, async () => {
    const prepared = await renderEmail({
      templateCode: "TICKET_ORDER_CONFIRMATION",
      to: "preview@example.invalid",
      context: { organization: 1 },
      substitutions: c.values,
    }, async () => ({ template: { id: 1, subject: c.subject, html: c.html } }));
    assert.equal(prepared.subject, c.expectedSubject);
    assert.equal(prepared.html, c.expectedHtml);
  });
}

Deno.test("actual rendering substitutes once regardless of value ordering or insertion order", async () => {
  const render = (substitutions: Record<string, string>) =>
    renderEmail(
      {
        templateCode: "TICKET_ORDER_CONFIRMATION",
        to: "preview@example.invalid",
        context: { organization: 1 },
        substitutions,
      },
      async () => ({
        template: {
          id: 1,
          subject: "{{orderSymbol}}",
          html: "<p>{{occasionTitle}} / {{orderSymbol}}</p>",
        },
      }),
    );
  for (
    const values of [
      { occasionTitle: "{{orderSymbol}}", orderSymbol: "ABC" },
      { orderSymbol: "ABC", occasionTitle: "{{orderSymbol}}" },
    ]
  ) {
    const prepared = await render(values);
    assert.equal(prepared.subject, "ABC");
    assert.equal(prepared.html, "<p>{{orderSymbol}} / ABC</p>");
  }
});
