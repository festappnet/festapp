/** Compatibility boundary for the installed Stripe reconciliation job. */
import { reconcilePayments } from "../payments/reconcile.ts";
import {
  stripePaymentAdapter,
  type StripePaymentsDependencies,
} from "../payments/connectors/stripe.ts";
export function reconcileStripePayments(
  deps: StripePaymentsDependencies,
  now = Date.now,
) {
  return reconcilePayments(stripePaymentAdapter(deps), now);
}
