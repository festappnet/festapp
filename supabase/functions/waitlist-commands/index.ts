import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import {
  prepareWaitlistDelivery,
  type WaitlistEmailContext,
} from "../_shared/waitlistEmail.ts";

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
    const { operation, payload, commandId, clientId } = await request.json();
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

    const deliveries = [];
    if (operation === "register" || operation === "send") {
      const { data, error } = await supabaseAdmin.rpc(
        "get_waitlist_email_context_v1",
        {
          p_operation: operation,
          p_payload: payload,
          p_actor: actor,
        },
      );
      if (error) {
        return respond({ code: 400, error: "waitlist_email_context_invalid" });
      }
      const contexts: WaitlistEmailContext[] = Array.isArray(data)
        ? data
        : [data];
      for (const context of contexts) {
        deliveries.push(
          await prepareWaitlistDelivery(
            context,
            operation === "register"
              ? "waitlist_confirmation"
              : "waitlist_offer",
          ),
        );
      }
    }
    const { data, error } = await supabaseAdmin.rpc(
      "execute_waitlist_command_client_sync_v1",
      {
        p_operation: operation,
        p_payload: payload,
        p_command_id: commandId,
        p_client_id: clientId,
        p_actor: actor,
        p_deliveries: deliveries,
      },
    );
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
    return respond(data);
  } catch {
    return respond({ code: 500, error: "waitlist_command_failed" }, 500);
  }
});
