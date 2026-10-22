import {
  type CheckoutSnapshot,
  record,
  StripeBoundaryError,
} from "./provider.ts";
export type StripeMovement = Readonly<{
  providerId: string;
  kind: "payment" | "refund";
  amountMinor: number;
  currency: string;
  occurredAt: number;
}>;
const reject = (): never => {
  throw new StripeBoundaryError("stripe_fact_mismatch");
};
function id(value: unknown): unknown {
  return typeof value === "string" ? value : record(value).id;
}
function amount(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) <= 0) return reject();
  return value as number;
}
function created(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) return reject();
  return value as number;
}
/** Only a current provider read in the saved connected-account scope is admissible.
 * `checkout.session.completed` alone and success/cancel URLs never authorize tickets.
 */
export function paymentFact(
  snapshot: CheckoutSnapshot,
  currentSession: unknown,
): StripeMovement | null {
  const s = record(currentSession);
  const pi = record(s.payment_intent);
  if (
    s.object !== "checkout.session" || s.livemode !== snapshot.livemode ||
    s.client_reference_id !== snapshot.attemptId ||
    s.amount_total !== snapshot.amountMinor ||
    s.currency !== snapshot.currency.toLowerCase() || s.mode !== "payment"
  ) return reject();
  if (s.payment_status !== "paid") return null;
  if (
    pi.object !== "payment_intent" || typeof pi.id !== "string" ||
    !/^pi_[A-Za-z0-9]+$/.test(pi.id) ||
    pi.status !== "succeeded" || pi.livemode !== snapshot.livemode ||
    pi.amount_received !== snapshot.amountMinor ||
    pi.amount !== snapshot.amountMinor ||
    pi.currency !== snapshot.currency.toLowerCase() ||
    record(pi.metadata).festapp_attempt !== snapshot.attemptId ||
    (pi.application_fee_amount != null && pi.application_fee_amount !== 0) ||
    pi.transfer_data != null || pi.on_behalf_of != null
  ) return reject();
  return {
    providerId: pi.id as string,
    kind: "payment",
    amountMinor: snapshot.amountMinor,
    currency: snapshot.currency,
    occurredAt: created(record(pi.latest_charge).created),
  };
}
/** Each successful refund is a separate immutable economic identity, never a delta
 * calculated from event order or charge.amount_refunded snapshots.
 */
export function refundFact(
  snapshot: CheckoutSnapshot,
  intentId: string,
  currentRefund: unknown,
): StripeMovement | null {
  const r = record(currentRefund);
  if (
    r.object !== "refund" || typeof r.id !== "string" ||
    !/^re_[A-Za-z0-9]+$/.test(r.id) ||
    id(r.payment_intent) !== intentId || !/^pi_[A-Za-z0-9]+$/.test(intentId) ||
    r.currency !== snapshot.currency.toLowerCase() ||
    amount(r.amount) > snapshot.amountMinor
  ) return reject();
  if (r.status !== "succeeded") return null;
  return {
    providerId: r.id as string,
    kind: "refund",
    amountMinor: amount(r.amount),
    currency: snapshot.currency,
    occurredAt: created(r.created),
  };
}
export type StripeDisputeFact = Readonly<{
  providerId: string;
  amountMinor: number;
  currency: string;
  status: string;
  hold: boolean;
}>;
export function disputeFact(
  snapshot: CheckoutSnapshot,
  intentId: string,
  currentDispute: unknown,
): StripeDisputeFact {
  const d = record(currentDispute);
  const statuses = [
    "warning_needs_response",
    "warning_under_review",
    "warning_closed",
    "needs_response",
    "under_review",
    "won",
    "lost",
  ];
  if (
    d.object !== "dispute" || typeof d.id !== "string" ||
    !/^(?:dp|du)_[A-Za-z0-9]+$/.test(d.id) ||
    d.livemode !== snapshot.livemode || id(d.payment_intent) !== intentId ||
    !/^pi_[A-Za-z0-9]+$/.test(intentId) ||
    d.currency !== snapshot.currency.toLowerCase() ||
    amount(d.amount) > snapshot.amountMinor ||
    typeof d.status !== "string" || !statuses.includes(d.status)
  ) return reject();
  // Proposed product policy: dispute hold does not create another refund movement.
  return {
    providerId: d.id as string,
    amountMinor: amount(d.amount),
    currency: snapshot.currency,
    status: d.status as string,
    hold: ["needs_response", "under_review", "lost"].includes(
      d.status as string,
    ),
  };
}
