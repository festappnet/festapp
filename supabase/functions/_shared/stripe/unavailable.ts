/** Public configuration error only; configured actions keep their origin/auth checks. */
export function stripeUnavailableResponse(request: Request): Response {
  const headers = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization,apikey,content-type,x-client-info",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
  };
  return request.method === "OPTIONS"
    ? new Response(null, { status: 204, headers })
    : Response.json({ error: "stripe_not_configured" }, {
      status: 503,
      headers,
    });
}
