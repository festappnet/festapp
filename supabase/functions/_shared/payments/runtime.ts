/** Composition root: the only common runtime file that names installed providers.
 * Provider credentials, onboarding and persistence stay with each connector.
 */
import {
  stripeConnectDependencies,
  stripePaymentDependencies,
} from "../stripe/environment.ts";
import { stripeConnectHandler } from "../stripe/connect.ts";
import { stripeWebhookHandler } from "../stripe/payments.ts";
import { stripePaymentAdapter } from "./connectors/stripe.ts";
import { barionPaymentDependencies } from "../barion/environment.ts";
import { PaymentRegistry } from "./registry.ts";

export const paymentRegistry = new PaymentRegistry([
  ["barion", barionPaymentDependencies, "barionPaymentSource"],
  ["stripe", () => {
    const deps = stripePaymentDependencies();
    return {
      ...stripePaymentAdapter(deps),
      connection: {
        handle: (request) =>
          stripeConnectHandler(request, stripeConnectDependencies()),
      },
      webhook: { handle: (request) => stripeWebhookHandler(request, deps) },
    };
  }, "stripePaymentSource"],
]);
