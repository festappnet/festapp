import { createFakturoidGateway } from "../send-ticket-order/fakturoid.ts";
import { assertEquals, assertRejects } from "jsr:@std/assert@1";
import { deleteOrderWithInvoice } from "./delete.ts";

function fixture(
  options: {
    forbidden?: boolean;
    providerFails?: boolean;
    sqlFails?: boolean;
    replay?: boolean;
    legacy?: boolean;
    gateway?: ReturnType<typeof createFakturoidGateway>;
  } = {},
) {
  const calls: string[] = [];
  const response = { code: 200, data: { orderId: 42 } };
  const user = {
    rpc(name: string) {
      calls.push(name);
      if (name === "get_order_deletion_context_v1") {
        return Promise.resolve({
          data: options.replay ? { response } : {
            hasFakturoid: true,
            commandId: options.legacy ? null : "checkout",
            variableSymbol: "123",
          },
          error: options.forbidden ? "denied" : null,
        });
      }
      return Promise.resolve({
        data: response,
        error: options.sqlFails ? "failed" : null,
      });
    },
  };
  const admin = {
    rpc(name: string) {
      calls.push(name);
      return Promise.resolve({
        data: [{ type: "FAKTUROID", data: { slug: "unit-account" } }],
        error: null,
      });
    },
  };
  const invoice = (request: any) => {
    calls.push("invoice");
    assertEquals(request.commandId, "checkout");
    assertEquals(request.config.slug, "unit-account");
    return options.providerFails
      ? Promise.reject(new Error("422"))
      : Promise.resolve();
  };
  return {
    calls,
    run: () =>
      deleteOrderWithInvoice(
        42,
        "delete-command",
        user,
        admin,
        options.gateway?.deleteInvoice ?? invoice,
      ),
    response,
  };
}

Deno.test("invoice deletion authorizes before credentials and provider, then uses the canonical user command", async () => {
  const f = fixture();
  assertEquals(await f.run(), f.response);
  assertEquals(f.calls, [
    "get_order_deletion_context_v1",
    "get_external_services",
    "invoice",
    "delete_order_client_sync_v1",
  ]);
});
Deno.test("forbidden callers never read credentials or delete an invoice", async () => {
  const f = fixture({ forbidden: true });
  await assertRejects(f.run, Error, "ORDER_DELETE_FORBIDDEN");
  assertEquals(f.calls, ["get_order_deletion_context_v1"]);
});
Deno.test("provider rejection preserves the order", async () => {
  const f = fixture({ providerFails: true });
  await assertRejects(f.run, Error, "422");
  assertEquals(f.calls.includes("delete_order_client_sync_v1"), false);
});
Deno.test("SQL failure after provider success is reported as incomplete", async () => {
  const f = fixture({ sqlFails: true });
  await assertRejects(f.run, Error, "ORDER_DELETE_INCOMPLETE");
});
Deno.test("a completed retry replays the receipt without provider work", async () => {
  const f = fixture({ replay: true });
  assertEquals(await f.run(), f.response);
  assertEquals(f.calls, ["get_order_deletion_context_v1"]);
});

for (
  const scenario of [
    "absent",
    "delete-404",
    "legacy-absent",
    "legacy-detail-404",
  ]
) {
  Deno.test(`order deletion completes when invoice was independently removed: ${scenario}`, async () => {
    const providerCalls: string[] = [];
    const gateway = createFakturoidGateway(
      (async (input, init) => {
        const url = String(input);
        const method = init?.method ?? "GET";
        providerCalls.push(`${method} ${url}`);
        if (url.endsWith("/oauth/token")) {
          return Response.json({ access_token: "test-token" });
        }
        if (scenario.endsWith("absent")) return Response.json([]);
        if (scenario === "delete-404" && method === "DELETE") {
          return new Response(null, { status: 404 });
        }
        if (scenario === "legacy-detail-404" && url.endsWith("/55.json")) {
          return new Response(null, { status: 404 });
        }
        return Response.json([{ id: 55, variable_symbol: "123" }]);
      }) as typeof fetch,
    );
    const f = fixture({ gateway, legacy: scenario.startsWith("legacy") });
    assertEquals(await f.run(), f.response);
    assertEquals(f.calls.at(-1), "delete_order_client_sync_v1");
    assertEquals(
      providerCalls.filter((call) => call.startsWith("DELETE")).length,
      scenario === "delete-404" ? 1 : 0,
    );
    assertEquals(
      providerCalls.filter((call) =>
        call.startsWith("POST") &&
        !call.endsWith("/oauth/token")
      ).length,
      0,
    );
  });
}
