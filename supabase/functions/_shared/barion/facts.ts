import {
  type CheckoutSnapshot,
  PaymentError,
  type PaymentObservation,
  record,
} from "../payments/contracts.ts";

export const barionId = (value: unknown): string => {
  if (
    typeof value !== "string" ||
    !/^(?:[a-f0-9]{32}|[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12})$/i.test(
      value,
    )
  ) {
    throw new PaymentError("barion_identity_invalid", true);
  }
  return value.replaceAll("-", "").toLowerCase();
};
function minor(value: unknown) {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new PaymentError("barion_amount_invalid", true);
  }
  const amount = Math.round(value * 100);
  if (
    !Number.isSafeInteger(amount) || amount <= 0 ||
    Math.abs(amount / 100 - value) > 1e-9
  ) {
    throw new PaymentError("barion_amount_invalid", true);
  }
  return amount;
}
function time(value: unknown, conservative = false) {
  if (
    typeof value !== "string" || !value.endsWith("Z") ||
    !Number.isFinite(Date.parse(value))
  ) {
    throw new PaymentError("barion_time_invalid", true);
  }
  return (conservative ? Math.ceil : Math.floor)(Date.parse(value) / 1000);
}

/** A complete authenticated PaymentState is the observation boundary. Unknown
 * movements/reversals hold admission; they never erase previously stored money.
 * TransactionTime exists at preparation, so payment timing uses CompletedAt.
 */
export function barionFacts(
  snapshot: CheckoutSnapshot,
  id: string,
  value: unknown,
): PaymentObservation {
  const state = record(value), paymentId = barionId(id);
  if (
    snapshot.livemode || barionId(state.PaymentId) !== paymentId ||
    state.PaymentRequestId !== snapshot.attemptId ||
    state.PaymentType !== "Immediate" || state.Currency !== snapshot.currency ||
    !Array.isArray(state.Transactions) || state.Transactions.length === 0 ||
    state.Transactions.length > 100 ||
    ![
      "Prepared",
      "Started",
      "InProgress",
      "Waiting",
      "Reserved",
      "Authorized",
      "Canceled",
      "Succeeded",
      "Failed",
      "PartiallySucceeded",
      "Expired",
    ].includes(String(state.Status))
  ) {
    throw new PaymentError("barion_state_invalid", true);
  }
  const movements: PaymentObservation["movements"][number][] = [];
  let held = false, original: string | null = null, refunded = 0;
  const seen = new Set<string>();
  // This connector supports one full original transaction, not marketplace splits.
  for (const raw of state.Transactions) {
    const tx = record(raw), txId = barionId(tx.TransactionId);
    if (seen.has(txId) || tx.Currency !== snapshot.currency) {
      throw new PaymentError("barion_transaction_invalid", true);
    }
    seen.add(txId);
    const type = tx.TransactionType;
    if (type === "CardPayment" || type === "Shop" || type === "Unspecified") {
      if (
        original || tx.POSTransactionId !== snapshot.attemptId ||
        minor(tx.Total) !== snapshot.amountMinor
      ) {
        throw new PaymentError("barion_original_invalid", true);
      }
      original = txId;
      if (tx.Status === "Succeeded" && state.Status === "Succeeded") {
        movements.push({
          providerId: txId,
          kind: "payment",
          amountMinor: snapshot.amountMinor,
          currency: snapshot.currency,
          occurredAt: time(state.CompletedAt, true),
        });
      } else if (
        !["Prepared", "Started", "Reserved", "Rejected", "Canceled", "Expired"]
          .includes(String(tx.Status))
      ) held = true;
    } else if (
      ["Refund", "RefundToBankCard", "RefundToBankAccount"].includes(
        String(type),
      )
    ) {
      const amount = minor(tx.Total);
      if (tx.RelatedId != null && barionId(tx.RelatedId) === txId) {
        throw new PaymentError("barion_refund_invalid", true);
      }
      if (tx.Status === "Succeeded") {
        refunded += amount;
        movements.push({
          providerId: txId,
          kind: "refund",
          amountMinor: amount,
          currency: snapshot.currency,
          occurredAt: time(tx.TransactionTime),
        });
      } else held = true;
    } else if (type !== "CardProcessingFee") {
      // Includes refund reversals and review/chargeback states whose complete
      // release semantics have not been established. Never infer a release.
      held = true;
    }
  }
  if (
    !original || refunded > snapshot.amountMinor ||
    (refunded > 0 && !movements.some((m) => m.kind === "payment"))
  ) {
    throw new PaymentError("barion_financial_state_invalid", true);
  }
  if (
    typeof state.Total !== "number" || !Number.isFinite(state.Total) ||
    state.Total < 0 ||
    (state.Total > snapshot.amountMinor / 100) ||
    (!held && state.Status === "Succeeded" &&
      Math.abs(state.Total - (snapshot.amountMinor - refunded) / 100) > 1e-9)
  ) {
    throw new PaymentError("barion_total_invalid", true);
  }
  // RelatedId is optional in real responses. Any supplied refund link must be
  // to the sole original transaction in this authenticated payment.
  for (const raw of state.Transactions) {
    const tx = record(raw);
    if (
      ["Refund", "RefundToBankCard", "RefundToBankAccount"].includes(
        String(tx.TransactionType),
      ) &&
      tx.RelatedId != null && barionId(tx.RelatedId) !== original
    ) throw new PaymentError("barion_refund_link_invalid", true);
  }
  return {
    checkoutId: paymentId,
    paymentId,
    checkoutStatus: state.Status === "Succeeded"
      ? "complete"
      : ["Canceled", "Expired"].includes(String(state.Status))
      ? "expired"
      : "open",
    movements,
    disputes: held
      ? [{
        providerId: `review-${paymentId}`,
        amountMinor: snapshot.amountMinor,
        currency: snapshot.currency,
        status: "unverified",
        hold: true,
      }]
      : [],
    connectorState: { financialHold: held ? "true" : null },
  };
}
