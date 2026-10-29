import { boundedRetryAfter } from "./retry-after.ts";
import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2.58.0";
import type { McpTenant } from "./config.ts";

type Dependencies = { config: McpTenant; admin: SupabaseClient; fetch?: typeof fetch };

/** A distinct non-minting management interface on the existing first-party
 * transport. Caller-supplied identities, destinations and consent IDs are rejected. */
export async function handleMcpManagement(req: Request, body: Record<string, unknown>, deps: Dependencies,
  json: (body: unknown, status?: number) => Response): Promise<Response> {
  const revoke = body.operation === "connections.revoke";
  const allowed = revoke ? ["operation", "connectionId"] : ["operation"];
  if (Object.keys(body).some(k => !allowed.includes(k)) ||
      (revoke && (typeof body.connectionId !== "string" || !/^[A-Za-z0-9_-]{1,200}$/.test(body.connectionId)))) {
    return json({ error: "invalid_request" }, 400);
  }
  const accessToken = req.headers.get("authorization")?.match(/^Bearer (.+)$/i)?.[1];
  if (!accessToken || accessToken.length >= 8192) return json({ error: "authentication_required" }, 401);
  const { data, error } = await deps.admin.auth.getUser(accessToken);
  if (error || !data.user) return json({ error: "authentication_required" }, 401);
  const target = await deps.admin.rpc("resolve_existing_user_session_v1", { p_user: data.user.id });
  if (target.error || target.data?.organization !== deps.config.organizationId) return json({ error: "forbidden" }, 403);
  const result = await (deps.fetch ?? fetch)(`${deps.config.issuer}/tenant-connections`, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(15000),
    headers: { "Content-Type": "application/json", "X-Festapp-Mcp-Broker": deps.config.brokerSecret },
    body: JSON.stringify({ operation: revoke ? "revoke" : "list", ...(revoke ? { connectionId: body.connectionId } : {}),
      accessToken, tenantId: deps.config.tenantId, tenantOrigin: deps.config.tenantOrigin, organizationId: deps.config.organizationId }),
  });
  if (!result.ok) {
    const response = json({ error: "connection_unavailable" }, [401, 403, 429].includes(result.status) ? result.status : 503);
    if (result.status === 429) response.headers.set("Retry-After", String(boundedRetryAfter(result.headers.get("Retry-After"))));
    return response;
  }
  const output = await result.json();
  if (revoke) {
    if (output.connectionId !== body.connectionId || output.revoked !== true) throw new Error();
    return json({ connectionId: output.connectionId, revoked: true });
  }
  if (!Array.isArray(output.connections)) throw new Error();
  return json({ connections: output.connections });
}
