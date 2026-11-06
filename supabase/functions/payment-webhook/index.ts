import { paymentHeaders } from "../_shared/payments/http.ts";
import { paymentRegistry } from "../_shared/payments/runtime.ts";
// The provider is routing information, never authentication. Each connector
// verifies the original signed bytes or reloads current authenticated state.
Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: paymentHeaders });
  }
  try {
    const binding = paymentRegistry.resolve(
      new URL(request.url).searchParams.get("provider"),
    );
    if (!binding.webhook) throw new Error("payment_webhook_unavailable");
    return await binding.webhook.handle(request);
  } catch {
    return Response.json({ error: "payment_webhook_unavailable" }, {
      status: 503,
      headers: paymentHeaders,
    });
  }
});
