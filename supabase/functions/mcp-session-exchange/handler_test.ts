import { assertEquals, assert } from "jsr:@std/assert@1";
import type { Session, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import { handleMcpExchange } from "./handler.ts";

const actor = "00000000-0000-4000-8000-000000000001";
const config = { tenantId: "fixture", tenantOrigin: "https://tenant.invalid", issuer: "https://mcp.invalid", organizationId: 3, brokerSecret: "s".repeat(43) };
function fixture({ invalidProof = false, wrongActor = false, failTransfer = false, organization = 3 } = {}) {
  const calls: string[] = [];
  const admin = {
    auth: { getUser: (token: string) => { calls.push(`proof:${token}`); return Promise.resolve({ error: invalidProof ? {} : null, data: { user: { id: actor } } }); },
      admin: { signOut: (_: string, scope: string) => { calls.push(`revoke:${scope}`); return Promise.resolve({ error: null }); } } },
    rpc: () => Promise.resolve({ data: { organization, authEmail: "verified@tenant.invalid" }, error: null }),
  } as unknown as SupabaseClient;
  const deps = { config, admin, makeAnon: () => admin,
    fetch: (async (url: string | URL | Request, init?: RequestInit) => {
      assertEquals(url, "https://mcp.invalid/tenant-connection");
      assertEquals((init!.headers as Record<string, string>)["X-Festapp-Mcp-Broker"], config.brokerSecret);
      const body = JSON.parse(init!.body as string); calls.push(body.operation);
      assertEquals(body.tenantId, "fixture"); assertEquals(body.organizationId, 3);
      if (body.operation === "prepare") return Response.json({ lease: "lease", userId: wrongActor ? "other" : actor, organizationId: 3 });
      if (body.operation === "check") return Response.json({ valid: true, userId: actor });
      if (body.operation === "complete") {
        assertEquals(body.session.refresh_token, "independent-refresh");
        assertEquals(body.accessToken, undefined);
        return Response.json({ resumeUrl: "https://mcp.invalid/connect/one/finish?resume=opaque" }, { status: failTransfer ? 503 : 200 });
      }
      return Response.json({ client: "Codex", occasions: [{ id: 7 }] });
    }) as typeof fetch,
    issue: (async (target, _admin, _anon, options) => {
      calls.push("mint"); assertEquals(target, { targetUserId: actor, expectedAuthEmail: "verified@tenant.invalid" });
      assert(await options!.validateContext!());
      return { access_token: "independent-access", refresh_token: "independent-refresh", user: { id: actor } } as Session;
    }) as typeof import("../_shared/issueExistingUserSession.ts").issueExistingUserSession,
  };
  const request = (operation = "approve", origin = config.tenantOrigin, token = "app-access") =>
    handleMcpExchange(new Request("https://api.invalid/mcp-session-exchange", { method: "POST",
      headers: { Origin: origin, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ request: "r".repeat(43), operation, occasions: [7], userId: "attacker", email: "attacker@invalid" }),
    }), deps);
  return { request, calls };
}
Deno.test("tenant proof and explicit consent mint only the verified actor and never return backend credentials", async () => {
  const f = fixture(); const response = await f.request(); assertEquals(response.status, 200);
  const body = await response.text(); assert(!body.includes("independent-refresh")); assert(!body.includes("independent-access"));
  assertEquals(f.calls, ["proof:app-access", "prepare", "mint", "proof:app-access", "check", "complete"]);
});
Deno.test("foreign origin and invalid identity cannot reach privileged mint", async () => {
  const f = fixture(); assertEquals((await f.request("approve", "https://evil.invalid")).status, 403); assertEquals(f.calls, []);
  const invalid = fixture({ invalidProof: true }); assertEquals((await invalid.request()).status, 401); assert(!invalid.calls.includes("mint"));
});
Deno.test("reading consent metadata or status and cancelling never mint a session", async () => {
  const f = fixture(); assertEquals((await f.request("details")).status, 200); assertEquals((await f.request("status")).status, 200); assertEquals((await f.request("cancel")).status, 200);
  assert(!f.calls.includes("mint"));
});
Deno.test("actor or tenant mismatch rejects before session issuance", async () => {
  for (const opts of [{ wrongActor: true }, { organization: 4 }]) {
    const f = fixture(opts); assertEquals((await f.request()).status, 403); assert(!f.calls.includes("mint"));
  }
});
Deno.test("an uncertain failed transfer revokes only the new independent session", async () => {
  const f = fixture({ failTransfer: true }); assertEquals((await f.request()).status, 403);
  assertEquals(f.calls.at(-1), "revoke:local");
});
