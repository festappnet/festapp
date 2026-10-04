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
    const body = await req.json();
    if (body.processQueue === true) {
      if (!body.requestSecret) {
        throw new AuthError("System authorization required", 401);
      }
      const actor = await authorizeRequest({
        requestSecret: body.requestSecret,
      });
      await emailRpc("wake_email_worker");
      return Response.json({ message: "Canonical worker scheduled" }, {
        headers,
      });
    }
    const orderId = body.data?.orderId ?? body.data?.order_id;
    if (
      typeof orderId !== "number" ||
      ![
        "TICKET_ORDER_UPDATE",
        "TICKET_ORDER_STORNO",
        "TICKET_ORDER_REMINDER",
        "TICKET_ORDER_PAYMENT_DONE",
      ].includes(body.code)
    ) {
      return Response.json({ error: "Invalid email request" }, {
        status: 400,
        headers,
      });
    }
    const details = await emailRpc("get_order_details_for_email", {
      p_order_id: orderId,
    });
    if (details.code !== 200) throw new Error("Order unavailable");
    const { occasion } = details.data;
    const actor = await authorizeRequest({
      requestSecret: body.requestSecret ?? body.data?.requestSecret,
      authorizationHeader: req.headers.get("Authorization"),
      occasionId: occasion.id,
    });
    // Do not persist caller bearer or request secrets.
    const data = {
      ...body.data,
      order_id: orderId,
      requested_by: actor.user?.id ?? null,
    };
    delete data.requestSecret;
    delete data.orderId;
    const queued = await emailRpc("enqueue_order_email", {
      p_code: body.code,
      p_data: data,
      p_org: occasion.organization,
      p_occ: occasion.id,
      p_unit: occasion.unit,
      ...(body.requestId ? { p_request: `manual:${body.requestId}` } : {}),
    });
    await awaitEmailAccepted(queued.message_id);
    return Response.json({ message: "Email sent successfully." }, { headers });
  } catch (e) {
    return Response.json({ error: "Email delivery pending or failed" }, {
      status: e instanceof AuthError ? e.status : 503,
      headers,
    });
  }
});
