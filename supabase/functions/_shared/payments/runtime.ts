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
import { builtinPaymentBinding } from "./connectors/builtin.ts";
import { createUserClient, supabaseAdmin } from "../supabaseUtil.ts";
import { hostedPaymentBinding } from "./contracts.ts";
import { stripeRefundCapability } from "./connectors/stripeRefund.ts";
import { PaymentRegistry } from "./registry.ts";

export const paymentRegistry = new PaymentRegistry([
  ...(["bank", "cash"] as const).map(id => [id, () => builtinPaymentBinding(id, async (name, args, authorization) => {
    if (!authorization) throw new Error("payment_authentication_required");
    const {data, error} = await createUserClient(authorization).rpc(name, args);
    if (error) throw error;
    return data;
  })] as const),
  ["barion", () => hostedPaymentBinding(barionPaymentDependencies()), "barionPaymentSource"],
  ["stripe", () => {
    const deps = stripePaymentDependencies();
    return hostedPaymentBinding({
      ...stripePaymentAdapter(deps),
      connection: {
        handle: (request) =>
          stripeConnectHandler(request, stripeConnectDependencies()),
      },
      webhook: { handle: (request) => stripeWebhookHandler(request, deps) },
    }, stripeRefundCapability(deps));
  }, "stripePaymentSource"],
]);

export async function paymentRefundRpc(name: string, args: Record<string, unknown>): Promise<unknown> {
  const {data, error} = await supabaseAdmin.rpc(name, args);
  if (error) throw new Error("payment_refund_service_rejected");
  return data;
}
