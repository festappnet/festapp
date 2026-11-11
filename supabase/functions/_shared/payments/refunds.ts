import {
  type ConnectorState, type RefundSnapshot, type RefundObservation,
  PaymentError, record,
} from "./contracts.ts";
import type { PaymentRegistry } from "./registry.ts";
import { synchronizePaymentClaim } from "./checkout.ts";

export type RefundRpc = (name: string, args: Record<string, unknown>) => Promise<unknown>;
function decodeSnapshot(value: unknown, providerId: string, requestId: string): RefundSnapshot & {attemptId: string} {
  const s = record(value);
  if (s.providerId !== providerId || s.requestId !== requestId || typeof s.attemptId !== "string" || !s.attemptId ||
      typeof s.accountId !== "string" || !s.accountId || typeof s.livemode !== "boolean" ||
      typeof s.paymentId !== "string" || !s.paymentId || !Number.isSafeInteger(s.amountMinor) || Number(s.amountMinor) <= 0 ||
      typeof s.currency !== "string" || !/^[A-Z]{3}$/.test(s.currency) ||
      !Number.isSafeInteger(s.createdAt) || Number(s.createdAt) < 0 ||
      typeof s.idempotencyKey !== "string" || s.idempotencyKey.length < 8 || s.idempotencyKey.length > 255)
    throw new PaymentError("payment_refund_claim_invalid");
  return s as RefundSnapshot & {attemptId: string};
}
function validateObservation(result: RefundObservation, snapshot: RefundSnapshot) {
  if (!["pending", "action_required", "succeeded", "failed", "cancelled", "unknown"].includes(result.status) ||
      typeof result.dispatchUncertain !== "boolean" ||
      (result.amountMinor != null && result.amountMinor !== snapshot.amountMinor) ||
      (result.currency != null && result.currency !== snapshot.currency) ||
      (result.status === "succeeded" && (!result.refundId || result.dispatchUncertain)))
    throw new PaymentError("payment_refund_observation_invalid");
  return result;
}
/** Claimed durable intents only. Unknown writes always recover by reading;
 * confirmed amounts still come exclusively from the existing provider ledger. */
export async function reconcilePaymentRefunds(registry: PaymentRegistry, rpc: RefundRpc) {
  const started = Date.now();
  const rows = await rpc("get_recoverable_payment_refunds", {});
  if (!Array.isArray(rows) || rows.length > 10) throw new PaymentError("payment_refund_queue_invalid");
  const results: {requestId: string; state: "completed" | "continuing" | "uncertain" | "skipped"}[] = [];
  for (const raw of rows) {
    if (Date.now() - started > 45_000) break;
    const row = record(raw), requestId = String(row.requestId ?? "");
    if (!/^[a-f0-9-]{36}$/.test(requestId) || !registry.has(row.providerId)) throw new PaymentError("payment_refund_queue_invalid");
    let lease: string | undefined;
    let observation: RefundObservation = {status: "unknown", dispatchUncertain: true};
    try {
      const binding = registry.resolve(row.providerId);
      if (!binding.refund) throw new PaymentError("payment_refund_unavailable");
      const claim = record(await rpc("claim_payment_refund", {p_request: requestId}));
      if (claim.disposition === "busy" || claim.disposition === "read") {
        results.push({requestId, state: "skipped"}); continue;
      }
      if (claim.requestId !== requestId || claim.providerId !== row.providerId ||
          typeof claim.lease !== "string" || typeof claim.priorDispatched !== "boolean")
        throw new PaymentError("payment_refund_claim_invalid");
      const snapshot = decodeSnapshot(claim.snapshot, String(row.providerId), requestId);
      if (!binding.refund.currencies.includes(snapshot.currency) ||
          (binding.hostedCheckout && binding.hostedCheckout.livemode !== snapshot.livemode))
        throw new PaymentError("payment_refund_claim_invalid");
      const state = record(claim.connectorState);
      if (Object.values(state).some(v => v !== null && typeof v !== "string")) throw new PaymentError("payment_refund_claim_invalid");
      lease = claim.lease;
      observation = validateObservation(await (claim.priorDispatched
        ? binding.refund.recoverRefund(snapshot, state as ConnectorState)
        : binding.refund.requestRefund(snapshot)), snapshot);
      // Read authoritative original payment state and ingest through its current
      // lease. Dispatch success by itself never becomes a financial movement.
      if (observation.refundId && binding.hostedCheckout) {
        const deps = binding.hostedCheckout;
        const sync = await deps.store.claimSync({attemptId: snapshot.attemptId, accountId: snapshot.accountId});
        if (sync.providerId !== snapshot.providerId || (sync.disposition === "dispatch" &&
            (sync.snapshot.attemptId !== snapshot.attemptId || sync.snapshot.accountId !== snapshot.accountId)))
          throw new PaymentError("payment_refund_claim_invalid");
        if (sync.disposition === "dispatch") await synchronizePaymentClaim(sync, null, deps);
      }
      await rpc("complete_payment_refund", {p_request: requestId, p_lease: lease, p_result: observation});
      results.push({requestId, state: observation.status === "unknown" ? "continuing" : "completed"});
    } catch {
      if (lease) await rpc("complete_payment_refund", {p_request: requestId, p_lease: lease, p_result: observation}).catch(() => {});
      results.push({requestId, state: "uncertain"});
    }
  }
  return results;
}
