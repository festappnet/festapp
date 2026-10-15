import { createUserClient, supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { prepareOrderOverviewSource } from "../_shared/waitlistEmail.ts";
import { openOrderOverviewUrl } from "../_shared/customerOrderAccess.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json", "Cache-Control": "no-store", "Referrer-Policy": "no-referrer",
};
const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers });
Deno.serve(async request => {
  if (request.method === "OPTIONS") return new Response("ok", { headers });
  if (request.method !== "POST") return respond({ code: 405 }, 405);
  try {
    const { token, offerId, orderId, commandId, admin = false, reissue = false } = await request.json();
    if (typeof commandId !== "string" || !/^[a-f0-9-]{36}$/i.test(commandId) ||
      (reissue !== true && reissue !== false) || (admin !== true && admin !== false) ||
      (!admin && !reissue && (typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token)))) return respond({ code: 403 }, 403);
    // Overview access is stable. This endpoint never rotates it or sends mail.
    if (reissue) return respond({ code: 403 }, 403);
    if (admin === true) {
      const authorization = request.headers.get("Authorization");
      if (!authorization || !Number.isSafeInteger(orderId) || orderId <= 0) return respond({ code: 403 }, 403);
      const user = createUserClient(authorization);
      const { data: actor, error: authError } = await user.auth.getUser();
      if (authError || !actor.user) return respond({ code: 403 }, 403);
      const { data: allowed, error: denied } = await user.rpc("get_order_overview_admin_context", { p_order_id: orderId });
      if (denied || !allowed) return respond({ code: 403 }, 403);
      const resolveAdmin = async (delivery: unknown = null) => {
        const { data, error } = await supabaseAdmin.rpc("get_order_email_overview_source_v1", {
          p_order_id: allowed.orderId, p_recipient: allowed.recipient, p_command_id: commandId, p_delivery: delivery,
        });
        if (error || !data) throw new Error("INVALID_CAPABILITY");
        return data;
      };
      let context = await resolveAdmin();
      if (!context.source) context = await resolveAdmin(await prepareOrderOverviewSource(context));
      return respond({ code: 200, url: await openOrderOverviewUrl(context, context.source) });
    }
    const params = { p_token: token, p_order_id: orderId ?? null, p_offer_id: offerId ?? null,
      p_command_id: commandId, p_actor: null, p_reissue: false };
    const resolve = async (delivery: unknown = null) => {
      const { data, error } = await supabaseAdmin.rpc("resolve_customer_order_access_v1", { ...params, p_delivery: delivery });
      if (error || data?.code !== 200) throw new Error("INVALID_CAPABILITY");
      return data;
    };
    let context = await resolve();
    if (!context.source) context = await resolve(await prepareOrderOverviewSource(context));
    const url = await openOrderOverviewUrl(context, context.source);
    return respond({ code: 200, url });
  } catch { return respond({ code: 403, errorCode: "INVALID_CAPABILITY" }, 403); }
});
