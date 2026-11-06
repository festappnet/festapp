import {
  assertEquals,
  assertStringIncludes,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import { confirmationSubstitutions } from "./confirmationContent.ts";
import { renderEmail } from "./emailDelivery.ts";

function order(currency = "CZK", amount = 0) {
  return {
    id: 1,
    order_symbol: "1A2C3E4F5G",
    state: "paid",
    occasion: { title: "Helpni víkendovka", features: [] },
    form: { data: {} },
    data: { email: "test@example.invalid", tickets: [], fields: [] },
    payment_info: {
      amount,
      currency_code: currency,
      account_number: null,
      account_number_human_readable: null,
      variable_symbol: null,
      creditor_reference: null,
      deadline: null,
    },
  };
}

for (const currency of ["CZK", "EUR"]) {
  Deno.test(`free ${currency} confirmation renders without bank or payment reference`, async () => {
    const values = confirmationSubstitutions(order(currency));
    assertEquals(values.variableSymbol, "");
    assertEquals(values.iban, "");
    assertStringIncludes(values.balanceReasoning, "považována za uhrazenou");
    const email = await renderEmail({
      to: "test@example.invalid",
      context: { organization: 3, unit: 11 },
      substitutions: values,
    }, async () => ({
      template: {
        id: 1,
        subject: "{{occasionTitle}} - Potvrzení rezervace",
        html:
          "<p>Ahoj, potvrzujeme Tvou rezervaci místa na akci {{occasionTitle}}.</p>",
      },
    }));
    assertEquals(email.subject, "Helpni víkendovka - Potvrzení rezervace");
    assertStringIncludes(email.html, "potvrzujeme Tvou rezervaci");
    assertEquals(email.attachments.length, 0);
  });
}

Deno.test("free confirmation preserves an already configured payment reference", () => {
  const czk = order();
  Object.assign(czk.payment_info, { variable_symbol: "12345" });
  assertEquals(confirmationSubstitutions(czk).variableSymbol, "12345");
  const eur = order("EUR");
  Object.assign(eur.payment_info, { creditor_reference: "RF18539007547034" });
  assertEquals(
    confirmationSubstitutions(eur).variableSymbol,
    "RF18539007547034",
  );
});

Deno.test("payable confirmations still require the correct payment reference", () => {
  assertThrows(
    () => confirmationSubstitutions(order("CZK", 100)),
    Error,
    "VS_REQUIRED",
  );
  assertThrows(
    () => confirmationSubstitutions(order("EUR", 100)),
    Error,
    "EUR_REFERENCE_REQUIRED",
  );
});

for (const currency of ['CZK','EUR']) {
  Deno.test(`cash ${currency} confirmation renders safely without bank reference`, async () => {
    const value = order(currency, 250.50);
    Object.assign(value.payment_info, {payment_method:'cash', data:{payment_policy:{mode:'none',cashInstructions:'U vstupu <script>alert(1)</script>'}}});
    const subs = confirmationSubstitutions(value);
    assertEquals(subs.variableSymbol,'');
    assertEquals(subs.deadline,null);
    assertStringIncludes(subs.balanceReasoning,'Rezervace potvrzena');
    assertStringIncludes(subs.balanceReasoning,'&lt;script&gt;');
    assertEquals(subs.balanceReasoning.includes('<script>'),false);
    const email = await renderEmail({to:'test@example.invalid',context:{organization:3,unit:11},substitutions:subs},async()=>({template:{id:1,subject:'Rezervace',html:'<p>{{balanceReasoning}}</p>'}}));
    assertEquals(email.attachments.length,0);
    assertEquals(email.html.includes('VS_REQUIRED'),false);
  });
}
