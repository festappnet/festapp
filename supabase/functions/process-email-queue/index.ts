import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { emailRpc } from "../_shared/emailQueueClient.ts";
import { renderQueuedEmail } from "../_shared/emailRenderer.ts";
import { sealEmail } from "../_shared/emailPayload.ts";
import { drainEmails } from "../_shared/emailDispatcher.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const body = await req.json();
    if (!body.requestSecret) {
      throw new AuthError("System authorization required", 401);
    }
    await authorizeRequest({ requestSecret: body.requestSecret });
    const gatewayUrl = Deno.env.get("EMAIL_GATEWAY_URL"),
      gatewayToken = Deno.env.get("EMAIL_GATEWAY_TOKEN");
    if (!gatewayUrl || !gatewayToken) throw new Error("gateway_unavailable");
    const quotaResponse = await fetch(gatewayUrl, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${gatewayToken}`,
      },
      body: JSON.stringify({ refreshQuota: true }),
      signal: AbortSignal.timeout(12000),
      redirect: "error",
    });
    if (!quotaResponse.ok) throw new Error("quota_refresh_unavailable");
    const result = await drainEmails({
      rpc: emailRpc,
      prepare: renderQueuedEmail,
      seal: sealEmail,
      now: Date.now,
      gateway: async (row) => {
        const url = Deno.env.get("EMAIL_GATEWAY_URL"),
          token = Deno.env.get("EMAIL_GATEWAY_TOKEN");
        if (!url || !token) throw new Error("email_gateway_unavailable");
        const response = await fetch(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${token}`,
          },
          body: JSON.stringify({
            attemptId: row.attempt_id,
            leaseToken: row.lease_token,
          }),
          signal: AbortSignal.timeout(20_000),
          redirect: "error",
        });
        if (!response.ok) throw new Error("email_gateway_failed");
      },
    });
    return new Response(JSON.stringify(result), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: "email_worker_failed" }), {
      status: e instanceof AuthError ? e.status : 500,
      headers,
    });
  }
});
