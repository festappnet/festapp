import {
  type PaymentClaim,
  type PaymentDependencies,
  PaymentError,
  type RecoveryAttempt,
  type RecoveryConnection,
} from "./contracts.ts";
import { recoverPaymentClaim } from "./checkout.ts";

export type PaymentReconcileResult = {
  attemptId?: string;
  connectionId?: string;
  operation?: "read_attempts" | "read_connections" | "purge_sources";
  state: "completed" | "continuing" | "skipped" | "uncertain";
};

/** Financial recovery has priority. Account/source maintenance is independent:
 * neither a maintenance failure nor its budget can suppress queued payments.
 */
export async function reconcilePayments(
  deps: PaymentDependencies,
  now = Date.now,
): Promise<PaymentReconcileResult[]> {
  const started = now();
  const hasBudget = () => now() - started < 45_000;
  const results: PaymentReconcileResult[] = [];
  const invalid = () =>
    new PaymentError(`${deps.connector.id}_recovery_invalid`);
  const diagnostic = (
    operation: string,
    attemptId?: string,
    claim?: PaymentClaim,
    error?: unknown,
  ) => {
    console.error(JSON.stringify({
      provider: deps.connector.id,
      operation,
      attemptId,
      retryClass: "uncertain",
      leaseLost: error instanceof PaymentError &&
        error.code === "payment_lease_lost",
      uncertaintyAgeSeconds: claim?.disposition === "dispatch"
        ? Math.max(0, Math.floor(now() / 1000) - claim.snapshot.createdAt)
        : null,
      correlationId: crypto.randomUUID(),
    }));
  };
  let work: readonly RecoveryAttempt[] = [];
  try {
    const rows = await deps.store.recoverableAttempts();
    if (
      !Array.isArray(rows) || rows.length > 10 ||
      rows.some((row) =>
        typeof row?.attemptId !== "string" || !row.attemptId ||
        typeof row?.accountId !== "string" || !row.accountId
      )
    ) throw invalid();
    work = rows;
  } catch (error) {
    diagnostic("read_attempts", undefined, undefined, error);
    results.push({ operation: "read_attempts", state: "uncertain" });
  }
  for (const item of work) {
    if (!hasBudget()) break;
    let claim: PaymentClaim | undefined;
    try {
      const candidate = await deps.store.claimSync(item);
      if (
        candidate.providerId !== deps.connector.id ||
        (candidate.disposition === "dispatch" &&
          (candidate.snapshot.attemptId !== item.attemptId ||
            candidate.snapshot.accountId !== item.accountId))
      ) {
        throw invalid();
      }
      // Only a claim bound to this queue item may dispatch or release its lease.
      claim = candidate;
      if (claim.disposition !== "dispatch") {
        results.push({ attemptId: item.attemptId, state: "skipped" });
        continue;
      }
      if (!hasBudget()) {
        await deps.store.failSync(item.attemptId, claim.lease);
        results.push({ attemptId: item.attemptId, state: "continuing" });
        break;
      }
      const payment = await recoverPaymentClaim(claim, deps);
      results.push({
        attemptId: item.attemptId,
        state: payment.reconciliationPending === true
          ? "continuing"
          : "completed",
      });
    } catch (error) {
      diagnostic("recover", item.attemptId, claim, error);
      if (claim?.disposition === "dispatch") {
        await deps.store.failSync(item.attemptId, claim.lease).catch(() => {});
      }
      results.push({ attemptId: item.attemptId, state: "uncertain" });
    }
  }
  if (deps.maintenance && hasBudget()) {
    let connections: readonly RecoveryConnection[] = [];
    try {
      const rows = await deps.maintenance.recoverableConnections();
      if (
        !Array.isArray(rows) || rows.length > 2 ||
        rows.some((row) =>
          typeof row?.connectionId !== "string" || !row.connectionId ||
          typeof row?.accountId !== "string" || !row.accountId
        )
      ) throw invalid();
      connections = rows;
    } catch (error) {
      diagnostic("read_connections", undefined, undefined, error);
      results.push({ operation: "read_connections", state: "uncertain" });
    }
    for (const { accountId, connectionId } of connections) {
      if (!hasBudget()) break;
      try {
        await deps.maintenance.observeConnection(accountId);
        results.push({ connectionId, state: "completed" });
      } catch (error) {
        diagnostic("observe_connection", undefined, undefined, error);
        results.push({ connectionId, state: "uncertain" });
      }
    }
  }
  // Expiry is enforced at capability authorization; delayed physical cleanup
  // cannot extend a token's validity or authorize another payment.
  if (hasBudget()) {
    try {
      await deps.store.purgeExpiredSources();
    } catch (error) {
      diagnostic("purge_sources", undefined, undefined, error);
      results.push({ operation: "purge_sources", state: "uncertain" });
    }
  }
  return results;
}
