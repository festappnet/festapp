import { stripeWebhookHandler } from "../_shared/stripe/payments.ts";
import { stripePaymentDependencies } from "../_shared/stripe/environment.ts";
Deno.serve(async (request) => {
  try {
    const dependencies = stripePaymentDependencies();
    if (dependencies.webhookSecrets.length === 0) {
      throw new Error("stripe_not_configured");
    }
    return await stripeWebhookHandler(request, dependencies);
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
