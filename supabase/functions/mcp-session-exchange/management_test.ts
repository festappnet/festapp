import { assertEquals, assert } from "jsr:@std/assert@1";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { handleMcpExchange } from "./handler.ts";
const config = { tenantId: "fixture", tenantOrigin: "https://tenant.invalid", issuer: "https://mcp.invalid", organizationId: 3, brokerSecret: "s".repeat(43) };
function fixture({ invalid = false, organization = 3, upstream = 200 } = {}) {
  const calls: unknown[] = [];
  const admin = { auth: { getUser: () => Promise.resolve({ data: { user: invalid ? null : { id: "verified-user" } }, error: null }) },
    rpc: (name: string, args: unknown) => { calls.push([name, args]); return Promise.resolve({ data: { organization }, error: null }); } } as unknown as SupabaseClient;
  const deps = { config, admin, makeAnon: () => { throw new Error("must not mint"); },
    issue: () => { throw new Error("must not issue"); },
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      assertEquals(url, config.issuer + "/tenant-connections");
      assertEquals(init?.redirect, "error");
      const body = JSON.parse(init!.body as string); calls.push(body);
      assertEquals(body.accessToken, "app-access");
      assertEquals(body.tenantId, "fixture"); assertEquals(body.organizationId, 3);
      assertEquals((init!.headers as Record<string, string>)["X-Festapp-Mcp-Broker"], config.brokerSecret);
      return Response.json(body.operation === "list" ? { connections: [], access_token: "must-not-leak" } : { connectionId: body.connectionId, revoked: true }, { status: upstream });
    }) as typeof fetch,
  };
  const request = (body: unknown, origin = config.tenantOrigin, authenticated = true) => handleMcpExchange(new Request("https://api.invalid/mcp-session-exchange", {
    method: "POST", headers: { origin, ...(authenticated ? { authorization: "Bearer app-access" } : {}), "content-type": "application/json" }, body: JSON.stringify(body),
  }), deps);
  return { calls, request };
}
Deno.test("management lists and revokes with current identity, without consent nonce or session issuance", async () => {
  const f = fixture();
  const response = await f.request({ operation: "connections.list" });
  assertEquals(response.status, 200); assertEquals(response.headers.get("cache-control"), "no-store");
  assertEquals(await response.json(), { connections: [] });
  assertEquals(await (await f.request({ operation: "connections.revoke", connectionId: "owned-grant" })).json(), { connectionId: "owned-grant", revoked: true });
  assertEquals(f.calls[0], ["resolve_existing_user_session_v1", { p_user: "verified-user" }]);
});
Deno.test("management rejects foreign origin, missing/invalid identity, tenant and client-selected authority", async () => {
  for (const [options, body, origin, auth, expected] of [
    [{}, { operation: "connections.list" }, "https://evil.invalid", true, 403],
    [{}, { operation: "connections.list" }, config.tenantOrigin, false, 401],
    [{ invalid: true }, { operation: "connections.list" }, config.tenantOrigin, true, 401],
    [{ organization: 4 }, { operation: "connections.list" }, config.tenantOrigin, true, 403],
    [{}, { operation: "connections.list", userId: "other" }, config.tenantOrigin, true, 400],
    [{}, { operation: "connections.revoke", connectionId: "../x" }, config.tenantOrigin, true, 400],
    [{}, { operation: "connections.list", request: "r".repeat(43) }, config.tenantOrigin, true, 400],
  ] as const) {
    const f = fixture(options); const response = await f.request(body, origin, auth); assertEquals(response.status, expected);
    assert(!f.calls.some(c => !Array.isArray(c)), "rejected input never reaches the issuer");
  }
});
Deno.test("management does not turn issuer refusal into success", async () => {
  const f = fixture({ upstream: 403 }); assertEquals((await f.request({ operation: "connections.revoke", connectionId: "foreign" })).status, 403);
});
