import { stripeUnavailableResponse } from "../_shared/stripe/unavailable.ts";
// Stripe redirects to the configured tenant route. That route removes the
// authorization code from history, authenticates the same Festapp user, then
// POSTs it here. A state nonce alone never authorizes account ownership.
import { stripeConnectHandler } from "../_shared/stripe/connect.ts";
import { stripeConnectDependencies } from "../_shared/stripe/environment.ts";
Deno.serve(async (request) => {
  try {
    return await stripeConnectHandler(
      request,
      stripeConnectDependencies(),
      true,
    );
  } catch {
    return stripeUnavailableResponse(request);
  }
});
