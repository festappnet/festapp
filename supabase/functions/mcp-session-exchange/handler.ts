import { boundedRetryAfter } from "./retry-after.ts";
import { handleMcpManagement } from "./management.ts";
import type { Session, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import type { McpTenant } from "./config.ts";
import { issueExistingUserSession } from "../_shared/issueExistingUserSession.ts";

type Dependencies = { config: McpTenant; admin: SupabaseClient; makeAnon: () => SupabaseClient; fetch?: typeof fetch;
  issue?: typeof issueExistingUserSession };

export async function handleMcpExchange(req: Request, deps: Dependencies): Promise<Response> {
  const { config, admin } = deps;
  const headers = { "Access-Control-Allow-Origin": config.tenantOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Expose-Headers": "Retry-After",
    "Access-Control-Allow-Methods": "POST, OPTIONS", "Vary": "Origin",
    "Cache-Control": "no-store", "Content-Type": "application/json" };
  const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
  let minted: Session | undefined;
  let transferred = false;
  try {
    if (req.headers.get("origin") !== config.tenantOrigin ||
        new URL(config.tenantOrigin).protocol !== "https:" ||
        new URL(config.issuer).protocol !== "https:" || config.brokerSecret.length < 43) return json({ error: "forbidden" }, 403);
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers });
    if (req.method !== "POST") return json({ error: "invalid_request" }, 405);
    // Bound the streamed body, including requests without Content-Length.
    const reader = req.body?.getReader();
    if (!reader) throw new Error();
    const chunks: Uint8Array[] = []; let size = 0;
    for (;;) {
      const { value, done } = await reader.read(); if (done) break;
      size += value.length; if (size > 8192) { await reader.cancel(); throw new Error(); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(size); let offset = 0;
    for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
    const body = JSON.parse(new TextDecoder().decode(bytes));
    if (["connections.list", "connections.revoke"].includes(body?.operation)) {
      return await handleMcpManagement(req, body, { config, admin, fetch: deps.fetch }, json);
    }
    if (!/^[A-Za-z0-9_-]{43}$/.test(body.request) || !["details", "approve", "cancel", "status"].includes(body.operation)) throw new Error();
    const broker = async (payload: Record<string, unknown>) => {
      const result = await (deps.fetch ?? fetch)(`${config.issuer}/tenant-connection`, {
        method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
        headers: { "Content-Type": "application/json", "X-Festapp-Mcp-Broker": config.brokerSecret },
        body: JSON.stringify({ ...payload, request: body.request, tenantId: config.tenantId,
          tenantOrigin: config.tenantOrigin, organizationId: config.organizationId }),
      });
      if (result.status === 429) throw Object.assign(new Error(), { rateLimited: true, retryAfter: boundedRetryAfter(result.headers.get("Retry-After")) });
      if (!result.ok) throw new Error();
      return await result.json();
    };
    if (body.operation === "cancel") return json({ ...await broker({ operation: "cancel" }), issuer: config.issuer });
    const accessToken = req.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
    if (!accessToken || accessToken.length > 8192) return json({ error: "authentication_required" }, 401);
    const { data, error } = await admin.auth.getUser(accessToken);
    if (error || !data.user) return json({ error: "authentication_required" }, 401);
    if (["details", "status"].includes(body.operation)) return json(await broker({ operation: body.operation, accessToken }));
    const prepared = await broker({ operation: "prepare", accessToken, access: body.access });
    if (prepared.userId !== data.user.id || prepared.organizationId !== config.organizationId || !prepared.lease) throw new Error();
    // Resolve from the verified actor, never a caller-supplied email/user ID.
    const target = await admin.rpc("resolve_existing_user_session_v1", { p_user: data.user.id });
    if (target.error || target.data?.organization !== config.organizationId || !target.data.authEmail) throw new Error();
    minted = await (deps.issue ?? issueExistingUserSession)(
      { targetUserId: data.user.id, expectedAuthEmail: target.data.authEmail }, admin, deps.makeAnon(), {
        validateContext: async () => {
          const current = await admin.auth.getUser(accessToken);
          if (current.error || current.data.user?.id !== data.user.id) return false;
          const live = await broker({ operation: "check", lease: prepared.lease });
          return live.valid === true && live.userId === data.user.id;
        },
      });
    const result = await broker({ operation: "complete", lease: prepared.lease,
      session: { access_token: minted.access_token, refresh_token: minted.refresh_token } });
    transferred = true;
    return json({ ...result, issuer: config.issuer });
  } catch (error) {
    if (minted && !transferred) await admin.auth.admin.signOut(minted.access_token, "local").catch(() => undefined);
    if (error && typeof error === "object" && "rateLimited" in error && "retryAfter" in error) {
      const response = json({ error: "connection_unavailable" }, 429);
      response.headers.set("Retry-After", String(error.retryAfter));
      return response;
    }
    return json({ error: "connection_unavailable" }, 403);
  }
}
