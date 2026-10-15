import { prepareOrderOverviewEmail } from "../_shared/orderOverviewEmail.ts";
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
    const { token, offerId, orderId, commandId, reissue = false } = await request.json();
    if (typeof commandId !== "string" || !/^[a-f0-9-]{36}$/i.test(commandId) ||
      (reissue !== true && reissue !== false) ||
      (!reissue && (typeof token !== "string" || !/^[a-f0-9]{64}$/.test(token)))) return respond({ code: 403 }, 403);
    let actor: string | null = null;
    if (reissue) {
      const auth = request.headers.get("Authorization");
      if (!auth) return respond({ code: 401 }, 401);
      const { data, error } = await createUserClient(auth).auth.getUser();
      if (error || !data.user) return respond({ code: 401 }, 401);
      actor = data.user.id;
    }
    const params = { p_token: token ?? null, p_order_id: orderId ?? null, p_offer_id: offerId ?? null,
      p_command_id: commandId, p_actor: actor, p_reissue: reissue };
    const resolve = async (delivery: unknown = null) => {
      const { data, error } = await supabaseAdmin.rpc("resolve_customer_order_access_v1", { ...params, p_delivery: delivery });
      if (error || data?.code !== 200) throw new Error("INVALID_CAPABILITY");
      return data;
    };
    let context = await resolve();
    if (!context.source) context = await resolve(await prepareOrderOverviewSource(context));
    const url = await openOrderOverviewUrl(context, context.source);
    let email = context.email;
    if (reissue && !email) {
      const prepared = await prepareOrderOverviewEmail(context, url);
      const queued = await supabaseAdmin.rpc("enqueue_order_overview_reissue_v1", {
        p_order_id: context.orderId, p_command_id: commandId, p_actor: actor,
        p_prepared: prepared.p_sealed, p_content_hash: prepared.p_content_hash,
      });
      if (queued.error) throw new Error("OVERVIEW_DELIVERY_FAILED");
      email = queued.data;
    }
    return respond({ code: 200, url, ...(reissue ? { email } : {}) });
  } catch { return respond({ code: 403, errorCode: "INVALID_CAPABILITY" }, 403); }
});
