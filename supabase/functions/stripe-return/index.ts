import { stripePaymentHandler } from "../_shared/stripe/payments.ts";
import { stripePaymentDependencies } from "../_shared/stripe/environment.ts";
Deno.serve(async (request) => {
  try {
    return await stripePaymentHandler(
      request,
      stripePaymentDependencies(),
      true,
    );
  } catch {
    return Response.json({ error: "stripe_not_configured" }, {
      status: 503,
      headers: {
        "Cache-Control": "no-store",
        "Referrer-Policy": "no-referrer",
      },
    });
  }
});
