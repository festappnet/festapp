import { AuthError, authorizeRequest } from "../_shared/auth.ts";
import { readStripeBytes } from "../_shared/stripe/payments.ts";
import { stripePaymentDependencies } from "../_shared/stripe/environment.ts";
import { reconcileStripePayments } from "../_shared/stripe/reconcile.ts";
Deno.serve(async (request) => {
  const headers = {
    "Cache-Control": "no-store",
    "Referrer-Policy": "no-referrer",
  };
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, {
      status: 405,
      headers,
    });
  }
  try {
    const body = JSON.parse(
      new TextDecoder().decode(await readStripeBytes(request, 1024)),
    );
    await authorizeRequest({
      requestSecret: typeof body.requestSecret === "string"
        ? body.requestSecret
        : undefined,
    });
    const results = await reconcileStripePayments(stripePaymentDependencies());
    return Response.json({ results }, {
      status: results.some((r) => r.state === "uncertain") ? 503 : 200,
      headers,
    });
  } catch (error) {
    return Response.json({
      error: error instanceof AuthError
        ? "unauthorized"
        : "stripe_recovery_unavailable",
    }, { status: error instanceof AuthError ? error.status : 503, headers });
  }
});
