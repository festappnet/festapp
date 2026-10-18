import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert";
import { createFakturoidGateway } from "./fakturoid.ts";
import {
  assertFakturoidVariableSymbol,
  buildFakturoidInvoicePayload,
} from "./fakturoidPayload.ts";

const config = {
  client_id: "test",
  client_secret: "test",
  slug: "test",
  subject_id: 1,
};

function order(currency: string, variableSymbol: string) {
  return {
    data: {},
    payment_info: {
      amount: 125.5,
      currency_code: currency,
      variable_symbol: variableSymbol,
      account_number: "CZ0000000000000000000000",
      account_number_human_readable: "000000-0000000000/0000",
    },
  };
}

function gateway(
  reply: (url: string, method: string, body?: Record<string, unknown>) => Response,
) {
  return createFakturoidGateway(((input: string | URL | Request, init?: RequestInit) => {
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    return Promise.resolve(reply(String(input), init?.method ?? "GET", body));
  }) as typeof fetch);
}

Deno.test("EUR proforma carries the VS used to derive the RF reference", () => {
  const payload = buildFakturoidInvoicePayload(
    order("EUR", "123456"), "Hvezda morska", "command-1", 42,
    "Tenant note", "2026-08-23",
  );
  assertEquals(payload.variable_symbol, "123456");
  assertEquals(payload.note, "Tenant note");
});

Deno.test("CZK proforma carries the application variable symbol", () => {
  const payload = buildFakturoidInvoicePayload(
    order("CZK", "987654"), "Long tenant unit", "command-2", 43,
    undefined, "2026-08-23",
  );
  assertEquals(payload.variable_symbol, "987654");
  assertEquals(
    (payload.lines as Array<{ unit_name: string }>)[0].unit_name,
    "Long tenan",
  );
});

Deno.test("EUR invoice must preserve the RF numeric VS", () => {
  assertFakturoidVariableSymbol({ variable_symbol: 987654 }, "987654");
  assertThrows(
    () => assertFakturoidVariableSymbol({ variable_symbol: "20260950" }, "987654"),
    Error, "FAKTUROID_VARIABLE_SYMBOL_MISMATCH",
  );
});

Deno.test("checkout preserves the application CZK VS without mutating its input", async () => {
  const sent: Record<string, unknown>[] = [];
  const client = gateway((url, method, body) => {
    if (url.endsWith("/oauth/token")) return Response.json({ access_token: "token" });
    if (method === "GET") return Response.json([]);
    sent.push(body!);
    return Response.json({ id: 55, variable_symbol: "987654" });
  });
  const input = order("CZK", "987654");
  const variableSymbol = await client.preparePayment({
    config, order: input, unitName: "Test unit", commandId: "command-1",
  });
  assertEquals(variableSymbol, "987654");
  assertEquals(input.payment_info.variable_symbol, "987654");
  assertEquals(sent.length, 1);
  assertEquals(sent[0].variable_symbol, "987654");
});

Deno.test("email phase cannot create a second proforma", async () => {
  const client = gateway((url) => url.endsWith("/oauth/token")
    ? Response.json({ access_token: "token" })
    : Response.json([]));
  await assertRejects(
    () => client.getEmailAttachment({ config, order: order("CZK", "1"), commandId: "command-1" }),
    Error, "FAKTUROID_INVOICE_NOT_READY",
  );
});

Deno.test("checkout keeps Fakturoid client when the form has no name", async () => {
  const methods: string[] = [];
  const client = gateway((url, method) => {
    methods.push(method);
    return url.endsWith("/oauth/token")
      ? Response.json({ access_token: "token" })
      : Response.json([{ id: 55, variable_symbol: "987654" }]);
  });
  const result = await client.preparePayment({
    config, order: order("CZK", "987654"), unitName: "Test unit",
    commandId: "command-1",
  });
  assertEquals(result, "987654");
  assertEquals(methods, ["POST", "GET"]);
});

Deno.test("checkout completes the client update before accepting a named buyer", async () => {
  const requests: Array<{ method: string; body?: Record<string, unknown> }> = [];
  const client = gateway((url, method, body) => {
    requests.push({ method, body });
    if (url.endsWith("/oauth/token")) return Response.json({ access_token: "token" });
    if (method === "GET") return Response.json([{ id: 55, variable_symbol: "123456" }]);
    return Response.json({ id: 55, variable_symbol: "123456" });
  });
  const input = order("EUR", "123456");
  input.data = { name: "Eva", surname: "Nováková" };
  const result = await client.preparePayment({
    config, order: input, unitName: "Test unit", commandId: "command-1",
  });
  assertEquals(result, "123456");
  assertEquals(requests.map((item) => item.method), ["POST", "GET", "PUT"]);
  assertEquals(requests[2].body?.client_name, "Eva Nováková");
  assertEquals(requests[2].body?.variable_symbol, "123456");
});

Deno.test("failed client update rejects checkout", async () => {
  const client = gateway((url, method) => {
    if (url.endsWith("/oauth/token")) return Response.json({ access_token: "token" });
    if (method === "GET") return Response.json([{ id: 55, variable_symbol: "123456" }]);
    return new Response("unavailable", { status: 503 });
  });
  const input = order("CZK", "123456");
  input.data = { name: "Eva" };
  await assertRejects(
    () => client.preparePayment({
      config, order: input, unitName: "Test unit", commandId: "command-1",
    }),
    Error, "Fakturoid patch failed 503",
  );
});

Deno.test("CZK invoice mismatch is rejected before any patch", async () => {
  const client = gateway((url, method) => url.endsWith("/oauth/token")
    ? Response.json({access_token:"token"}) : method === "GET"
    ? Response.json([{id:1,variable_symbol:"99"}]) : (()=>{throw Error("must not patch");})());
  await assertRejects(()=>client.preparePayment({config,order:order("CZK","42"),unitName:"Test",commandId:"same"}),Error,"FAKTUROID_VARIABLE_SYMBOL_MISMATCH");
});
Deno.test("ambiguous invoice lookup cannot select the first document or create another", async () => {
  const client=gateway(url=>url.endsWith("/oauth/token")?Response.json({access_token:"token"}):Response.json([{id:1},{id:2}]));
  await assertRejects(()=>client.preparePayment({config,order:order("CZK","42"),unitName:"Test",commandId:"same"}),Error,"FAKTUROID_INVOICE_LOOKUP_AMBIGUOUS");
});

Deno.test("invoice deletion uses checkout identity and DELETE, never POST invoice creation", async () => {
  const calls: string[] = [];
  const client = gateway((url, method) => {
    if (url.endsWith('/oauth/token')) return Response.json({ access_token: 'token' });
    calls.push(`${method} ${url}`);
    return method === 'DELETE' ? new Response(null, { status: 204 })
      : Response.json([{ id: 55, variable_symbol: '123' }]);
  });
  await client.deleteInvoice({ config, commandId: 'checkout', variableSymbol: '123' });
  assertEquals(calls, [
    'GET https://app.fakturoid.cz/api/v3/accounts/test/invoices.json?custom_id=checkout',
    'DELETE https://app.fakturoid.cz/api/v3/accounts/test/invoices/55.json',
  ]);
});

for (const status of [403, 422, 429, 500]) {
  Deno.test(`invoice deletion rejects provider status ${status}`, async () => {
    const client = gateway((url, method) => url.endsWith('/oauth/token')
      ? Response.json({ access_token: 'token' })
      : method === 'DELETE' ? new Response(null, { status })
      : Response.json([{ id: 55, variable_symbol: '123' }]));
    await assertRejects(() => client.deleteInvoice({ config, commandId: 'checkout', variableSymbol: '123' }), Error, `Fakturoid delete failed ${status}`);
  });
}

Deno.test('invoice deletion is idempotent when the invoice is already absent', async () => {
  const client = gateway((url) => url.endsWith('/oauth/token')
    ? Response.json({ access_token: 'token' }) : Response.json([]));
  await client.deleteInvoice({ config, commandId: 'checkout', variableSymbol: '123' });
});

Deno.test('legacy deletion uses fulltext search and verifies the detailed VS', async () => {
  const calls: string[] = [];
  const client = gateway((url, method) => {
    calls.push(`${method} ${url}`);
    if (url.endsWith('/oauth/token')) return Response.json({ access_token: 'token' });
    if (url.includes('/search.json?query=123')) return Response.json([{ id: 55 }]);
    if (method === 'DELETE') return new Response(null, { status: 204 });
    return Response.json({ id: 55, variable_symbol: '123' });
  });
  await client.deleteInvoice({ config, variableSymbol: '123' });
  assertEquals(calls.at(-1), 'DELETE https://app.fakturoid.cz/api/v3/accounts/test/invoices/55.json');
  assertEquals(calls.length, 4);
});

Deno.test('invoice deletion rejects ambiguous lookup and a mismatched VS', async () => {
  for (const invoices of [[{ id: 1 }, { id: 2 }], [{ id: 1, variable_symbol: '999' }]]) {
    let deleted = false;
    const client = gateway((url, method) => {
      if (method === 'DELETE') deleted = true;
      return url.endsWith('/oauth/token') ? Response.json({ access_token: 'token' }) : Response.json(invoices);
    });
    await assertRejects(() => client.deleteInvoice({ config, commandId: 'checkout', variableSymbol: '123' }));
    assertEquals(deleted, false);
  }
});
