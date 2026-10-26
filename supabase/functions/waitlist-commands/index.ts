import { executeWaitlistOperation } from "./executeOperation.ts";
import { openOrderOverviewUrl } from "../_shared/customerOrderAccess.ts";
import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { prepareWaitlistDelivery } from "../_shared/waitlistEmail.ts";

const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
const operations = new Set([
  "register",
  "send",
  "decline",
  "cancel",
  "withdraw",
  "preview_accept",
]);
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const respond = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") {
    return respond({ error: "method_not_allowed" }, 405);
  }
  try {
    const { operation, payload, commandId, clientId, administration } =
      await request.json();
    if (
      !operations.has(operation) || !payload || Array.isArray(payload) ||
      typeof payload !== "object" || typeof commandId !== "string" ||
      typeof clientId !== "string" || !uuid.test(commandId) ||
      !uuid.test(clientId)
    ) {
      return respond({ code: 400, error: "invalid_waitlist_command" }, 400);
    }

    let actor: string | null = null;
    const authorization = request.headers.get("Authorization");
    const anonymous = Deno.env.get("SUPABASE_ANON_KEY");
    if (authorization && authorization !== `Bearer ${anonymous}`) {
      const { data, error } = await createUserClient(authorization).auth
        .getUser();
      if (error || !data.user) {
        return respond({ code: 401, error: "unauthorized" }, 401);
      }
      actor = data.user.id;
    }
    if ((operation === "send" || operation === "cancel") && !actor) {
      return respond({ code: 401, error: "unauthorized" }, 401);
    }

    const { data, error } = await executeWaitlistOperation({
      operation,
      payload,
      commandId,
      clientId,
      actor,
      administration,
      userRpc: (name, args) => createUserClient(authorization!).rpc(name, args),
      serviceRpc: (name, args) => supabaseAdmin.rpc(name, args),
      prepareDelivery: prepareWaitlistDelivery,
    });
    if (error) {
      // SQL domain failures contain a controlled envelope. Never echo request
      // payloads, capabilities, provider errors, or arbitrary database details.
      try {
        const domain = JSON.parse(error.message);
        if (domain && typeof domain.errorCode === "string") {
          return respond(domain);
        }
      } catch { /* Non-domain SQL failures use the stable transport error. */ }
      return respond({ code: 400, error: "waitlist_command_failed" });
    }
    if (operation === "register") {
      const result = data?.data || data;
      if (result?.code === 200 && result.order?.id) {
        try {
          const source = await supabaseAdmin.rpc(
            "get_registered_order_overview_source_v1",
            {
              p_order_id: result.order.id,
              p_command_id: commandId,
            },
          );
          if (!source.error) {
            const url = await openOrderOverviewUrl(
              source.data,
              source.data.source,
            );
            return respond(
              data?.data
                ? { ...data, data: { ...result, orderOverviewUrl: url } }
                : { ...data, orderOverviewUrl: url },
            );
          }
        } catch {
          /* Registration succeeded; the queued email remains the delivery path. */
        }
      }
    }
    return respond(data);
  } catch {
    return respond({ code: 500, error: "waitlist_command_failed" }, 500);
  }
});
