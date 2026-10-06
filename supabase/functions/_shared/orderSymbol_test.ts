import { assertEquals, assertRejects, assertStringIncludes } from "https://deno.land/std@0.168.0/testing/asserts.ts";
import { generateFullOrder, withOrderIdentity } from "./orderOverview.ts";
import { renderEmail } from "./emailDelivery.ts";

Deno.test("old pending/replay reads identity once without replacing snapshot", async () => {
  const old = { id: 73, occasion: { id: 4, organization: 2 }, data: { price: 15, tickets: ["original"] } };
  const bytes = JSON.stringify(old);
  let calls = 0;
  const read = async (params: any) => { calls++; assertEquals(params, { p_order: 73, p_occasion: 4, p_organization: 2 }); return "7G4K9M2R6A"; };
  const enriched = await withOrderIdentity(old, read);
  assertEquals(enriched.order_symbol, "7G4K9M2R6A");
  assertEquals(enriched.data, old.data);
  assertEquals(JSON.stringify(old), bytes);
  assertEquals(await withOrderIdentity(enriched, read), enriched);
  assertEquals(calls, 1);
  await assertRejects(() => withOrderIdentity(old, async () => null), Error, "order_identity_unavailable");
});

for (const lang of ["cs", "en"] as const) {
  Deno.test(`overview ${lang} trusts explicit persisted identity, preserves style and prices`, () => {
    const html = generateFullOrder({ order_symbol: "spoofed", email: "a@example.invalid" }, [], [], lang, "7G4K9M2R6A");
    assertStringIncludes(html, `${lang === "cs" ? "Přehled objednávky" : "Order Overview"} 7G4K9M2R6A</p>`);
    assertEquals(html.split("7G4K9M2R6A").length, 2);
    assertEquals(html.includes(lang === "cs" ? "Symbol objednávky:" : "Order symbol:"), false);
    assertEquals(html.includes("spoofed"), false);
    assertStringIncludes(html, "background-color: #f9fafb");
    assertEquals(generateFullOrder({}, [], [], lang).includes("Order #"), false);
  });
}

for (const code of ["TICKET_ORDER_CONFIRMATION", "TICKET_ORDER_UPDATE", "TICKET_ORDER_STORNO", "TICKET_ORDER_PAYMENT_DONE", "TICKET_ORDER_REMINDER", "ORDER_TICKETS"]) {
  for (const lang of ["cs", "en"]) {
    Deno.test(`${code}/${lang} default MIME fields carry symbol, custom without placeholder stays unchanged and preserve payment references`, async () => {
      for (const hasIdentity of [true, false]) {
        const template = { id: 1, subject: `${lang === "cs" ? "Objednávka" : "Order"}${hasIdentity ? " {{orderSymbol}}" : ""}`, html: `<div style="color:#123456">{{variableSymbol}} / {{reference}}${hasIdentity ? " {{orderSymbol}}" : ""}</div>` };
        const before = JSON.stringify(template);
        const mail = await renderEmail({ to: "own@example.invalid", templateCode: code, context: { organization: 2 }, substitutions: { orderSymbol: "7G4K9M2R6A", variableSymbol: "12345", reference: "RF18539007547034" } }, async () => ({ template, wrapper: { html: "<main>{{content}}</main>" } }));
        if (hasIdentity) {
          assertStringIncludes(mail.subject, "7G4K9M2R6A"); assertStringIncludes(mail.html, "7G4K9M2R6A");
        } else {
          assertEquals(mail.subject.includes("7G4K9M2R6A"), false);
          assertEquals(mail.html.includes("7G4K9M2R6A"), false);
        }
        assertStringIncludes(mail.html, "color:#123456"); assertStringIncludes(mail.html, "12345 / RF18539007547034");
        assertEquals(JSON.stringify(template), before);
        assertEquals(mail.html.split("7G4K9M2R6A").length, hasIdentity ? 2 : 1);
      }
    });
  }
}
