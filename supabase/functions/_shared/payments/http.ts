import { checkoutHandoff, checkoutPayment } from "./checkout.ts";
import { type PaymentDependencies, PaymentError, record } from "./contracts.ts";

export const paymentHeaders = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};

export async function readPaymentBytes(request: Request, limit: number) {
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let length = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > limit) {
      await reader.cancel();
      throw new PaymentError("payment_request_too_large");
    }
    chunks.push(value);
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}

export async function paymentHandler(
  request: Request,
  deps: PaymentDependencies,
  readOnly = false,
) {
  const origin = request.headers.get("Origin");
  if (origin && !deps.allowedOrigins.includes(origin)) {
    return Response.json({ error: "origin_denied" }, {
      status: 403,
      headers: paymentHeaders,
    });
  }
  const cors = {
    ...paymentHeaders,
    ...(origin
      ? { "Access-Control-Allow-Origin": origin, "Vary": "Origin" }
      : {}),
    "Access-Control-Allow-Headers":
      "content-type,authorization,apikey,x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, {
      status: 405,
      headers: cors,
    });
  }
  try {
    const body = record(
      JSON.parse(
        new TextDecoder().decode(await readPaymentBytes(request, 4096)),
      ),
    );
    if (
      typeof body.token !== "string" || !/^[a-f0-9]{64}$/.test(body.token) ||
      (body.provider !== undefined && body.provider !== deps.connector.id) ||
      Object.keys(body).some((key) =>
        key !== "provider" && key !== "token" && (readOnly || key !== "action")
      ) ||
      (body.action !== undefined &&
        !["status", "prepare", "handoff", "status_handoff"].includes(
          String(body.action),
        ))
    ) {
      return Response.json({ error: "invalid_request" }, {
        status: 400,
        headers: cors,
      });
    }
    const result = readOnly
      ? { payment: await deps.store.readReturn(body.token) }
      : body.action === "status"
      ? { payment: await deps.store.readStatus(body.token) }
      : body.action === "handoff" || body.action === "status_handoff"
      ? await checkoutHandoff(body.token, deps, body.action === "handoff")
      : await checkoutPayment(body.token, deps);
    return Response.json(result, { headers: cors });
  } catch (error) {
    if (error instanceof PaymentError && error.code === "invalid_capability") {
      return Response.json({ error: error.code }, {
        status: 403,
        headers: cors,
      });
    }
    if (
      error instanceof PaymentError && error.code === "payment_rate_limited"
    ) {
      return Response.json({ error: error.code }, {
        status: 429,
        headers: { ...cors, "Retry-After": "60" },
      });
    }
    return Response.json({
      error: `${deps.connector.id}_payment_temporarily_unavailable`,
    }, { status: 503, headers: cors });
  }
}
