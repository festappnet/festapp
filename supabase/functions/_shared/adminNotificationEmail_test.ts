import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import {
  adminNotificationEmail,
  type DigestContext,
} from "./adminNotificationEmail.ts";
Deno.test("digest renders escaped authorized contributions, separate currencies and safe tenant links without RPC", () => {
  const context: DigestContext = {
    locale: "cs",
    address: "viewer@example.test",
    fingerprint: "f",
    items: [
      {
        key: "e1",
        kind: "order_payment_received",
        organizationId: 1,
        organizationTitle: "<Pořadatel>",
        occasionId: 3,
        occasionTitle: "Ples",
        occasionLink: "ples",
        webLink: "https://tenant.example.test",
        orderId: 1,
        facts: { count: 2, amount: 10, currency: "CZK" },
        sources: [],
      },
      {
        key: "e2",
        kind: "order_payment_received",
        organizationId: 1,
        organizationTitle: "<Pořadatel>",
        occasionId: 3,
        occasionTitle: "Ples",
        occasionLink: "ples",
        webLink: "javascript:alert(1)",
        orderId: 2,
        facts: { count: 1, amount: 20, currency: "EUR" },
        sources: [],
      },
    ],
  };
  const email = adminNotificationEmail(context, "noreply@example.test");
  assertEquals(email.subject, "Souhrn administrátorských oznámení");
  assertStringIncludes(email.html, "&lt;Pořadatel&gt;");
  assertStringIncludes(email.html, "Přijaté platby: 2");
  assertStringIncludes(email.html, "Kč");
  assertStringIncludes(email.html, "€");
  assertEquals(email.html.includes("javascript:"), false);
  assertEquals(email.attachments, []);
});
Deno.test("renderer obtains one authorized SQL context with explicit recipient and never loads item DTOs", async () => {
  Deno.env.set("SUPABASE_URL", "http://127.0.0.1:55499");
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "fixture-service-key");
  const calls: string[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (url: string | URL | Request) => {
    calls.push(String(url));
    return new Response(
      JSON.stringify({
        locale: "en",
        address: "viewer@example.test",
        fingerprint: "authorized-snapshot",
        items: [{
          key: "e",
          kind: "order_created",
          organizationId: 1,
          organizationTitle: "Organizer",
          occasionId: 2,
          occasionTitle: "Ball",
          facts: { count: 3 },
          sources: [],
        }],
      }),
      { headers: { "content-type": "application/json" } },
    );
  }) as typeof fetch;
  try {
    const { renderAdminNotificationEmail } = await import(
      "./adminNotificationEmail.ts"
    );
    const result = await renderAdminNotificationEmail({
      data: { dispatchId: "fixture-dispatch" },
      recipient: "viewer@example.test",
      recipient_user: "fixture-recipient",
    });
    assertEquals(calls.length, 1);
    assertEquals(
      calls[0].endsWith("/rpc/get_notification_center_email_context"),
      true,
    );
    assertEquals(
      result.postAction.notification_fingerprint,
      "authorized-snapshot",
    );
  } finally {
    globalThis.fetch = original;
  }
});
Deno.test("one shared bank item links each authorized tenant context without multiplying the incident", () => {
  const first = {
    organizationId: 1,
    organizationTitle: "Spolek A",
    occasionId: null,
    occasionTitle: null,
    occasionLink: null,
    webLink: "https://a.example.test",
    orderId: null,
    unitId: 11,
    bankAccountId: 22,
  };
  const second = {
    organizationId: 2,
    organizationTitle: "Spolek B",
    occasionId: null,
    occasionTitle: null,
    occasionLink: null,
    webLink: "https://b.example.test",
    orderId: null,
    affectedOccasions: [{ id: 3, title: "Ples B", link: "ples-b" }],
  };
  const result = adminNotificationEmail({
    locale: "cs",
    address: "recipient@example.test",
    fingerprint: "f",
    items: [{
      ...first,
      key: "bank:1:incident:one",
      kind: "bank_problem",
      facts: { count: null },
      sources: [first, second],
    }],
  }, "sender@example.test");
  assertStringIncludes(result.html, "Problém bankovního spojení: 1");
  assertStringIncludes(
    result.html,
    "https://a.example.test/unit/11/edit/bank-accounts/22/connection",
  );
  assertStringIncludes(
    result.html,
    "https://b.example.test/ples-b/reservations/orders/current",
  );
  assertStringIncludes(result.html, "Spolek B: Ples B");
});
Deno.test("reassignment is presented separately from new income and never as newly registered people", () => {
  const source = {
    organizationId: 1,
    organizationTitle: "Spolek",
    occasionId: 2,
    occasionTitle: "Ples",
    occasionLink: "ples",
    webLink: "https://a.example.test",
    orderId: 3,
  };
  const email = adminNotificationEmail({
    locale: "cs",
    address: "recipient@example.test",
    fingerprint: "f",
    items: [
      {
        ...source,
        key: "old-money-assigned",
        kind: "order_payment_received",
        facts: { count: null, amount: 50, currency: "CZK", reassigned: true },
        sources: [source],
      },
      {
        ...source,
        key: "new-money",
        kind: "order_payment_received",
        facts: { count: null, amount: 20, currency: "CZK", reassigned: false },
        sources: [source],
      },
    ],
  }, "sender@example.test");
  assertStringIncludes(email.html, "Přiřazení přijaté platby: 1");
  assertStringIncludes(email.html, "Přijaté platby: 1");
  assertEquals(email.html.includes("Přijaté platby: 2"), false);
  assertEquals(email.html.includes("Vstupenky:"), false);
});
Deno.test("large activity stays in one bounded HTML summary with an authorized overflow link", () => {
  const items = Array.from({ length: 200 }, (_, i) => {
    const source = {
      organizationId: i,
      organizationTitle: "Pořadatel ".repeat(80),
      occasionId: i,
      occasionTitle: "Ples ".repeat(80),
      occasionLink: "ples-" + i,
      webLink: "https://tenant.example.test",
      orderId: i,
    };
    return {
      ...source,
      key: "event:" + i,
      kind: "order_created",
      facts: { count: 2 },
      sources: [source],
    };
  });
  const result = adminNotificationEmail({
    locale: "cs",
    address: "recipient@example.test",
    fingerprint: "f",
    items,
  }, "sender@example.test");
  assertEquals(new TextEncoder().encode(result.html).length < 64_000, true);
  assertStringIncludes(result.html, "Další změny:");
  assertStringIncludes(result.html, "https://tenant.example.test/");
});

Deno.test("required gateway incidents use the same localized digest and authorized unit link", () => {
  const source = {
    organizationId: 1, organizationTitle: "Pořadatel", occasionId: null,
    occasionTitle: null, occasionLink: null, webLink: "https://tenant.example.test",
    orderId: null, unitId: 42, provider: "Stripe",
  };
  const html = adminNotificationEmail({
    locale: "cs", address: "admin@example.test", fingerprint: "authorized",
    items: [{ ...source, key: "gateway-episode", kind: "provider_problem", facts: { count: null }, sources: [source] }],
  }, "noreply@example.test").html;
  assertStringIncludes(html, "Problém platební brány: 1");
  assertStringIncludes(html, "https://tenant.example.test/unit/42/edit");
  assertStringIncludes(html, "Pořadatel: Stripe");
  assertEquals(html.includes("Vstupenky:"), false);
});
