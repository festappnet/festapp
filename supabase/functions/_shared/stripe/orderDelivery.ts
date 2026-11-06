/** Existing order-delivery callers delegate to the provider-neutral engine. */
import { prepareOrderDelivery } from "../payments/orderDelivery.ts";
import {
  stripePaymentAdapter,
  type StripePaymentsDependencies,
} from "../payments/connectors/stripe.ts";
export function prepareStripeOrderDelivery(
  source: unknown,
  orderId: number,
  commandId: string,
  surface: unknown,
  payment: unknown,
  deps: StripePaymentsDependencies,
) {
  return prepareOrderDelivery(
    source,
    orderId,
    commandId,
    surface,
    payment,
    stripePaymentAdapter(deps),
  );
}
