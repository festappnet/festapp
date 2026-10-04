import { supabaseAdmin } from "../_shared/supabaseUtil.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { awaitEmailAccepted, emailRpc } from "../_shared/emailQueueClient.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const { orderId, email, requestSecret, requestId } = await req.json();
    if (
      typeof orderId !== "number" || typeof email !== "string" ||
      !email.includes("@")
    ) {
      return Response.json({ error: "Invalid input parameters" }, {
        status: 400,
        headers,
      });
    }
    const details = await emailRpc("get_order_details_for_email", {
      p_order_id: orderId,
    });
    if (details.code !== 200) throw new Error("Order unavailable");
    const { order, occasion } = details.data;
    const actor = await authorizeRequest({
      requestSecret,
      authorizationHeader: req.headers.get("Authorization"),
      occasionId: occasion.id,
    });
    const payload = {
      order_id: orderId,
      requested_by: actor.user?.id ?? null,
      ...(email !== order.data.email ? { recipient: email, manual: true } : {}),
    };
    const result = await emailRpc("enqueue_order_email", {
      p_code: "ORDER_TICKETS",
      p_data: payload,
      p_org: occasion.organization,
      p_occ: occasion.id,
      p_unit: occasion.unit,
      ...(requestId
        ? { p_request: `resend:${requestId}:${orderId}:${email}` }
        : {}),
    });
    await awaitEmailAccepted(result.message_id);
    return Response.json({ message: "Tickets sent successfully", code: 200 }, {
      headers,
    });
  } catch (e) {
    return Response.json({ error: "Ticket delivery pending or failed" }, {
      status: e instanceof AuthError ? e.status : 503,
      headers,
    });
  }
});
