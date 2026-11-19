import { abuseLimitDetails } from "../_shared/abuseLimit.ts";
import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { emailRpc } from "../_shared/emailQueueClient.ts";
const headers = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Content-Type": "application/json",
};
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers });
  try {
    const { orderId, email, requestSecret, requestId, firstDelivery = false } =
      await req.json();
    if (
      typeof orderId !== "number" || typeof email !== "string" ||
      !email.includes("@") || typeof firstDelivery !== "boolean"
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
      ...(requestId && !firstDelivery
        ? { p_request: `resend:${requestId}:${orderId}:${email}` }
        : {}),
    });
    if (result?.state === "accepted") {
      return Response.json(
        { message: "Tickets sent successfully", code: 200 },
        {
          headers,
        },
      );
    }
    if (
      result?.message_id &&
      ["pending", "blocked", "preparing", "sending", "retry_wait"].includes(
        result.state,
      )
    ) {
      return Response.json({ message: "Ticket email queued", code: 202 }, {
        status: 202,
        headers,
      });
    }
    if (result?.state === "unknown") {
      return Response.json({ error: "ticket_delivery_unknown" }, {
        status: 409,
        headers,
      });
    }
    if (
      ["dead", "cancelled", "expired", "suppressed", "skipped"].includes(
        result?.state,
      )
    ) {
      return Response.json({ error: "ticket_delivery_unavailable" }, {
        status: 409,
        headers,
      });
    }
    throw new Error("Missing ticket delivery state");
  } catch (e) {
    const error = e as { code?: string; details?: string };
    if (error?.code === "PT429") {
      const limit = abuseLimitDetails(error.details);
      return Response.json(limit, {
        status: 429,
        headers: {
          ...headers,
          ...(limit.retryAfterSeconds
            ? { "Retry-After": String(limit.retryAfterSeconds) }
            : {}),
        },
      });
    }
    return Response.json({ error: "Ticket delivery unavailable" }, {
      status: e instanceof AuthError ? e.status : 503,
      headers,
    });
  }
});
