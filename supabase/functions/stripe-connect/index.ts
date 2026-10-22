import { stripeUnavailableResponse } from "../_shared/stripe/unavailable.ts";
import { stripeConnectHandler } from "../_shared/stripe/connect.ts";
import { stripeConnectDependencies } from "../_shared/stripe/environment.ts";
Deno.serve(async (request) => {
  try {
    return await stripeConnectHandler(request, stripeConnectDependencies());
  } catch {
    return stripeUnavailableResponse(request);
  }
});
