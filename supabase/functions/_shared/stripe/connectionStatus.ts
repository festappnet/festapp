import { record, StripeBoundaryError } from "./provider.ts";
import type { StripePaymentsDependencies } from "./payments.ts";

/** Old webhook snapshots cannot revoke a newly authorized account: read the
 * current account under a lease and commit only that current observation. */
export async function observeStripeConnection(
  accountId: string,
  deps: StripePaymentsDependencies,
  event: Record<string, unknown> | null = null,
) {
  const claim = record(
    await deps.rpc("claim_stripe_connection_status_internal", {
      p_account: accountId,
      p_livemode: deps.livemode,
    }),
  );
  if (claim.disposition === "unrelated") return "unrelated";
  if (claim.disposition !== "dispatch") {
    throw new StripeBoundaryError("stripe_connection_status_busy", true);
  }
  try {
    await deps.verifyPlatform();
    let status: unknown;
    try {
      status = await deps.provider.account(accountId);
    } catch (error) {
      if (
        !(error instanceof StripeBoundaryError) ||
        error.code !== "stripe_account_access_unavailable"
      ) throw error;
      status = { accountId, accessUnavailable: true };
    }
    const result = record(
      await deps.rpc("commit_stripe_connection_status_internal", {
        p_connection: claim.connectionId,
        p_lease: claim.lease,
        p_status: status,
        p_event: event,
      }),
    );
    if (result.committed !== true) {
      throw new StripeBoundaryError(
        "stripe_connection_status_not_committed",
        true,
      );
    }
    return "completed";
  } catch (error) {
    await deps.rpc("fail_stripe_connection_status_internal", {
      p_connection: claim.connectionId,
      p_lease: claim.lease,
    }).catch(() => {});
    throw error;
  }
}
