import { record } from "./provider.ts";
import { observeStripeConnection } from "./connectionStatus.ts";
import {
  recoverStripeClaim,
  type StripePaymentsDependencies,
} from "./payments.ts";

/** One bounded invocation. All money/domain effects use the webhook ingest. */
export async function reconcileStripePayments(
  deps: StripePaymentsDependencies,
  now = Date.now,
) {
  await deps.rpc("purge_expired_stripe_sources_internal", { p_limit: 100 });
  const work = await deps.rpc("get_recoverable_stripe_attempts_internal", {
    p_livemode: deps.livemode,
    p_limit: 10,
  });
  if (!Array.isArray(work) || work.length > 10) {
    throw new Error("stripe_recovery_invalid");
  }
  const started = now(),
    results: { attemptId?: string; connectionId?: string; state: string }[] =
      [];
  const connections = await deps.rpc(
    "get_recoverable_stripe_connections_internal",
    { p_livemode: deps.livemode },
  );
  if (!Array.isArray(connections) || connections.length > 2) {
    throw new Error("stripe_recovery_invalid");
  }
  for (const raw of connections) {
    if (now() - started > 45_000) break;
    const accountId = record(raw).accountId,
      connectionId = record(raw).connectionId;
    if (typeof accountId !== "string" || typeof connectionId !== "string") {
      throw new Error("stripe_recovery_invalid");
    }
    try {
      await observeStripeConnection(accountId, deps);
      results.push({ connectionId, state: "completed" });
    } catch {
      results.push({ connectionId, state: "uncertain" });
    }
  }
  for (const raw of work) {
    if (now() - started > 45_000) break;
    const item = record(raw);
    if (
      typeof item.attemptId !== "string" || typeof item.accountId !== "string"
    ) throw new Error("stripe_recovery_invalid");
    let claim: Record<string, unknown> | undefined;
    try {
      claim = record(
        await deps.rpc("claim_stripe_sync_internal", {
          p_account: item.accountId,
          p_livemode: deps.livemode,
          p_attempt: item.attemptId,
        }),
      );
      if (claim.disposition !== "dispatch") {
        results.push({ attemptId: item.attemptId, state: "skipped" });
        continue;
      }
      const payment = await recoverStripeClaim(claim, deps);
      results.push({
        attemptId: item.attemptId,
        state: payment.reconciliationPending === true
          ? "continuing"
          : "completed",
      });
    } catch {
      if (typeof claim?.lease === "string") {
        await deps.rpc("fail_stripe_reconciliation_internal", {
          p_attempt: item.attemptId,
          p_lease: claim.lease,
        }).catch(() => {});
      }
      results.push({ attemptId: item.attemptId, state: "uncertain" });
    }
  }
  return results;
}
