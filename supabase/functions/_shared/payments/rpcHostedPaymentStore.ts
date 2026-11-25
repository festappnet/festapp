import {
  decodeCommitReceipt,
  decodePaymentClaim,
  PaymentError,
  type PaymentStore,
  record,
} from "./contracts.ts";

export type HostedPaymentRpc = (
  operation: string,
  args: Record<string, unknown>,
) => Promise<unknown>;

/** Decode the service-only RPC contract shared by hosted payment stores. */
export function createRpcHostedPaymentStore(
  providerId: string,
  rpc: HostedPaymentRpc,
): PaymentStore {
  const claim = async (operation: string, args: Record<string, unknown>) =>
    decodePaymentClaim(await rpc(operation, args), providerId);
  const view = (value: unknown) => {
    const v = record(value);
    if (v.method !== providerId || typeof v.status !== "string") {
      throw new PaymentError(`${providerId}_view_invalid`);
    }
    return v;
  };
  return {
    claimCheckout: (token) => claim("claim_checkout", { token }),
    commitCheckout: async (snapshot, lease, checkout) =>
      decodeCommitReceipt(
        await rpc("commit_checkout", {
          attemptId: snapshot.attemptId,
          lease,
          checkout,
        }),
        providerId,
      ),
    failCheckout: async (snapshot, lease) => {
      await rpc("fail", { attemptId: snapshot.attemptId, lease });
    },
    ingest: async (snapshot, lease, _event, facts) =>
      decodeCommitReceipt(
        await rpc("ingest", { attemptId: snapshot.attemptId, lease, facts }),
        providerId,
      ),
    deferRecovery: async (c, result) => {
      await rpc("defer", {
        attemptId: c.snapshot.attemptId,
        lease: c.lease,
        seconds: result.retryAfterSeconds,
      });
    },
    readReturn: async (token) =>
      view(await rpc("read", { token, scope: "return_read" })),
    readStatus: async (token) =>
      view(await rpc("read", { token, scope: "order_pay" })),
    readHandoff: async (token, consume) => {
      const v = record(await rpc("handoff", { token, consume }));
      return consume ? { source: v.source } : { payment: view(v.payment) };
    },
    attachHandoff: async (orderId, commandId, tokenHash) => {
      await rpc("attach_handoff", { orderId, commandId, tokenHash });
    },
    purgeExpiredSources: async () => {
      const n = await rpc("purge", {});
      if (!Number.isSafeInteger(n) || Number(n) < 0 || Number(n) > 100) {
        throw new PaymentError(`${providerId}_recovery_invalid`);
      }
      return Number(n);
    },
    recoverableAttempts: async () => {
      const rows = await rpc("recoverable", {});
      if (
        !Array.isArray(rows) || rows.length > 10 ||
        rows.some((r) =>
          typeof r?.attemptId !== "string" || typeof r?.accountId !== "string"
        )
      ) {
        throw new PaymentError(`${providerId}_recovery_invalid`);
      }
      return rows;
    },
    claimSync: (item) => claim("claim_sync", item),
    failSync: async (attemptId, lease) => {
      await rpc("fail", { attemptId, lease });
    },
  };
}
