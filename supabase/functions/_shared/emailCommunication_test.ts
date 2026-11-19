import assert from "node:assert/strict";
import { communicationTones } from "./communicationTone.ts";
import {
  orderCommunication,
  resolveEmailLanguage,
} from "./emailCommunication.ts";
import { renderEmail } from "./emailDelivery.ts";
import { ticketEmailSubstitutions } from "./ticketEmail.ts";
import { confirmationPaymentSubstitutions } from "./orderEmailPresentation.ts";
import examples from "./emailPreviewScenarios.json" with { type: "json" };

const sql = await Deno.readTextFile(
  new URL(
    "../../../database/seeds/order_symbol_email_defaults.sql",
    import.meta.url,
  ),
);
const defaults = new Map(
  [...sql.matchAll(/\('([^']+)','([^']*)','((?:[^']|'')*)'\)/g)]
    .map((
      m,
    ) => [m[1], { id: 1, subject: m[2], html: m[3].replaceAll("''", "'") }]),
);

Deno.test("all five global order defaults use the same communication block", async () => {
  assert.equal(defaults.size, 5);
  for (const code of defaults.keys()) {
    for (const tone of communicationTones) {
      const sample = examples.records.find((r) =>
        r.templateCode === code && r.locale === "cs" && r.tone === tone
      )!;
      assert.ok(sample, `${code}/${tone} preview exists`);
      assert.ok(defaults.get(code)!.html.includes("{{orderCommunication}}"));
      const result = await renderEmail(
        {
          to: "preview@example.invalid",
          templateCode: code,
          context: { organization: 1 },
          substitutions: sample.values,
        },
        async () => ({
          template: defaults.get(code)!,
          wrapper: { html: "<main>{{content}}</main>" },
        }),
      );
      assert.ok(result.html.includes(tone === "formal" ? "Dobrý den" : "Ahoj"));
      assert.doesNotMatch(
        result.html,
        tone === "formal"
          ? /\bAhoj\b|Tvá |Tvou |Tvé /
          : /Dobrý den|Vaše |Vaši |Vaší /,
      );
      assert.doesNotMatch(result.html, /\{\{/);
    }
  }
});

Deno.test("communication preserves authored copy and escapes event names", async () => {
  assert.ok(
    orderCommunication(
      "TICKET_ORDER_CONFIRMATION",
      "<img src=x onerror=alert(1)>",
      "formal",
    ).includes("&lt;img"),
  );
  assert.throws(() => orderCommunication("unknown", "Akce", "formal"));
  assert.equal(resolveEmailLanguage("en"), "en");
  assert.equal(resolveEmailLanguage("__proto__"), "cs");
  const html = "<p>Ahoj, vlastní text pořadatele.</p>";
  const result = await renderEmail({
    to: "preview@example.invalid",
    templateCode: "TICKET_ORDER_CONFIRMATION",
    context: { organization: 1 },
    substitutions: {
      orderCommunication: orderCommunication(
        "TICKET_ORDER_CONFIRMATION",
        "Akce",
        "formal",
      ),
    },
  }, async () => ({ template: { id: 1, html, subject: "Vlastní předmět" } }));
  assert.equal(result.html, html);
});

Deno.test("cash fallback follows the same tone and preserves configured instructions", () => {
  const payment = { payment_method: "cash", amount: 800, currency_code: "CZK" };
  for (const tone of communicationTones) {
    const result = confirmationPaymentSubstitutions(payment, [], "cs", tone);
    assert.ok(
      result.balanceReasoning.includes(
        tone === "formal" ? "Zaplaťte prosím" : "Zaplať prosím",
      ),
    );
    const custom = confirmationPaymentSubstitutions(
      {
        ...payment,
        data: { payment_policy: { cashInstructions: "Vlastní pokyny." } },
      },
      [],
      "cs",
      tone,
    );
    assert.ok(custom.balanceReasoning.includes("Vlastní pokyny."));
  }
});

Deno.test("ticket delivery renders free and paid subjects from the order total", async () => {
  const code = "TICKET_ORDER_PAYMENT_DONE";
  for (const [price, language, expected] of [
    [0, "cs", "Potvrzení rezervace"],
    [0, "en", "Registration confirmed"],
    [120, "cs", "Přijatá platba"],
    [120, "en", "Payment received"],
  ] as const) {
    const substitutions = ticketEmailSubstitutions({
      order: { price, currency_code: "CZK", order_symbol: "PREVIEW", data: { tickets: [] } },
      occasion: { title: "Handling dětí", features: [] },
      payment_info: { amount: price, paid: price, payment_method: "bank", currency_code: "CZK" },
    }, language);
    const result = await renderEmail({
      to: "preview@example.invalid",
      templateCode: code,
      context: { organization: 1 },
      substitutions,
    }, async () => ({ template: defaults.get(code)! }));
    assert.equal(result.subject, 'Handling dětí - ' + expected);
    if (price === 0) {
      assert.match(result.html, language === "cs" ? /Rezervace je zdarma/ : /free of charge/);
      assert.doesNotMatch(result.html, /platb[ayě]|uhrazen|payment|paid/i);
    } else {
      assert.match(result.html, language === "cs" ? /přijetí platby/ : /receipt of payment/);
    }
  }
});
