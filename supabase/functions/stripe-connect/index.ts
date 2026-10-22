import { stripeConnectHandler } from "../_shared/stripe/connect.ts";
import { stripeConnectDependencies } from "../_shared/stripe/environment.ts";
Deno.serve(async (request) => {
  try {
    return await stripeConnectHandler(request, stripeConnectDependencies());
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
