import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import { useFakturoid } from "./fakturoid.ts";
import {
  assertFakturoidVariableSymbol,
  buildFakturoidInvoicePayload,
} from "./fakturoidPayload.ts";

function order(currency: string, variableSymbol: string) {
  return {
    payment_info: {
      amount: 125.5,
      currency_code: currency,
      variable_symbol: variableSymbol,
      account_number: "CZ0000000000000000000000",
      account_number_human_readable: "000000-0000000000/0000",
    },
  };
}

Deno.test("EUR proforma preserves the numeric VS used by RF payment", () => {
  const payload = buildFakturoidInvoicePayload(
    order("EUR", "123456"),
    "Hvezda morska",
    "command-1",
    42,
    "Tenant note",
    "2026-08-23",
  );
  assertEquals(payload.variable_symbol, "123456");
  assertEquals(payload.note, "Tenant note");
  assertEquals(payload.currency, "EUR");
});

Deno.test("CZK proforma preserves the order VS shown in payment QR", () => {
  const payload = buildFakturoidInvoicePayload(
    order("CZK", "987654"),
    "Long tenant unit",
    "command-2",
    43,
    undefined,
    "2026-08-23",
  );
  assertEquals(payload.variable_symbol, "987654");
  assertEquals(
    (payload.lines as Array<{ unit_name: string }>)[0].unit_name,
    "Long tenan",
  );
});

Deno.test("Fakturoid response must not replace the displayed payment VS", () => {
  assertFakturoidVariableSymbol({ variable_symbol: 987654 }, "987654");
  assertThrows(
    () =>
      assertFakturoidVariableSymbol({ variable_symbol: "20260950" }, "987654"),
    Error,
    "FAKTUROID_VARIABLE_SYMBOL_MISMATCH",
  );
});

Deno.test("CZK invoice creation and patch retain the customer-facing VS", async () => {
  const originalFetch = globalThis.fetch;
  const sent: Array<{ method: string; body: Record<string, unknown> }> = [];
  globalThis.fetch = async (_input, init) => {
    const method = init?.method ?? "GET";
    if (method === "POST" && String(_input).endsWith("/oauth/token")) {
      return Response.json({ access_token: "test-token" });
    }
    if (method === "GET") return Response.json([]);
    sent.push({ method, body: JSON.parse(String(init?.body)) });
    return Response.json({ id: 55, variable_symbol: "987654" });
  };
  try {
    await useFakturoid(
      { client_id: "test", client_secret: "test", slug: "test", subject_id: 1 },
      { ...order("CZK", "987654"), data: {} },
      "Test unit",
      "test-command",
      [],
    );
    assertEquals(sent.map((request) => request.body.variable_symbol), [
      "987654",
      "987654",
    ]);
  } finally {
    globalThis.fetch = originalFetch;
  }
});

Deno.test("CZK invoice rejects a different VS returned after patch", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_input, init) => {
    if (String(_input).endsWith("/oauth/token")) {
      return Response.json({ access_token: "test-token" });
    }
    if ((init?.method ?? "GET") === "GET") return Response.json([]);
    return Response.json({ id: 55, variable_symbol: "20260950" });
  };
  try {
    await assertRejects(
      () =>
        useFakturoid(
          {
            client_id: "test",
            client_secret: "test",
            slug: "test",
            subject_id: 1,
          },
          { ...order("CZK", "987654"), data: {} },
          "Test unit",
          "test-command",
          [],
        ),
      Error,
      "FAKTUROID_VARIABLE_SYMBOL_MISMATCH",
    );
  } finally {
    globalThis.fetch = originalFetch;
  }
});
