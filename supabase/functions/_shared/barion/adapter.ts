import {
  type CheckoutSnapshot,
  decodeCommitReceipt,
  decodePaymentClaim,
  type DispatchClaim,
  type PaymentConnector,
  type PaymentDependencies,
  PaymentError,
  type PaymentStore,
  record,
} from "../payments/contracts.ts";
import { paymentHeaders, readPaymentBytes } from "../payments/http.ts";
import { BarionSandboxProvider } from "./provider.ts";
import { barionFacts, barionId } from "./facts.ts";

export type BarionDependencies = {
  provider: BarionSandboxProvider;
  rpc(operation: string, args: Record<string, unknown>): Promise<unknown>;
  allowedOrigins: readonly string[];
  verifyPlatform(): Promise<void>;
  openSource: PaymentDependencies["openSource"];
  prepareSource(): Promise<unknown>;
};
export class BarionPaymentConnector implements PaymentConnector {
  readonly id = "barion";
  readonly displayName = "Barion sandbox";
  readonly recoveryRequiresSource = false;
  constructor(private readonly provider: BarionSandboxProvider) {}
  validateCheckoutUrl(value: string) {
    return this.provider.validateCheckoutUrl(value);
  }
  async createOrRecoverCheckout(snapshot: CheckoutSnapshot) {
    const remote = await this.provider.createPayment(snapshot);
    return {
      id: barionId(remote.id),
      url: this.validateCheckoutUrl(
        `https://secure.test.barion.com/Pay?Id=${barionId(remote.id)}`,
      ),
      expiresAt: snapshot.expiresAt,
      status: remote.status === "Succeeded"
        ? "complete" as const
        : "open" as const,
    };
  }
  async checkout(snapshot: CheckoutSnapshot, id: string) {
    const facts = barionFacts(
      snapshot,
      id,
      await this.provider.paymentState(snapshot, id),
    );
    return {
      id: barionId(id),
      url: this.validateCheckoutUrl(
        `https://secure.test.barion.com/Pay?Id=${barionId(id)}`,
      ),
      status: facts.checkoutStatus,
      expiresAt: snapshot.expiresAt,
    };
  }
  recoverCheckout(claim: DispatchClaim, _snapshot: CheckoutSnapshot) {
    // No documented lookup/retention guarantee. Never create from recovery.
    return Promise.resolve(
      claim.checkoutId
        ? { kind: "found" as const, checkoutId: claim.checkoutId }
        : {
          kind: "unresolved" as const,
          reason: "barion_payment_id_unknown",
          retryAfterSeconds: 120,
        },
    );
  }
  async observePayment(snapshot: CheckoutSnapshot, id: string) {
    return barionFacts(
      snapshot,
      id,
      await this.provider.paymentState(snapshot, id),
    );
  }
}
export function barionPaymentAdapter(
  deps: BarionDependencies,
): PaymentDependencies {
  const rpc = deps.rpc;
  const claim = async (operation: string, args: Record<string, unknown>) =>
    decodePaymentClaim(await rpc(operation, args), "barion");
  const view = (value: unknown) => {
    const v = record(value);
    if (v.method !== "barion" || typeof v.status !== "string") {
      throw new PaymentError("barion_view_invalid");
    }
    return v;
  };
  const store: PaymentStore = {
    claimCheckout: (token) => claim("claim_checkout", { token }),
    commitCheckout: async (snapshot, lease, checkout) =>
      decodeCommitReceipt(
        await rpc("commit_checkout", {
          attemptId: snapshot.attemptId,
          lease,
          checkout,
        }),
        "barion",
      ),
    failCheckout: async (snapshot, lease) => {
      await rpc("fail", { attemptId: snapshot.attemptId, lease });
    },
    ingest: async (snapshot, lease, _event, facts) =>
      decodeCommitReceipt(
        await rpc("ingest", { attemptId: snapshot.attemptId, lease, facts }),
        "barion",
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
        throw new PaymentError("barion_recovery_invalid");
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
        throw new PaymentError("barion_recovery_invalid");
      }
      return rows;
    },
    claimSync: (item) => claim("claim_sync", item),
    failSync: async (attemptId, lease) => {
      await rpc("fail", { attemptId, lease });
    },
  };
  const binding: PaymentDependencies = {
    livemode: false,
    allowedOrigins: deps.allowedOrigins,
    routes: {
      payPath: "/payments/barion/pay",
      returnPath: "/payments/barion/return",
    },
    connector: new BarionPaymentConnector(deps.provider),
    store,
    verifyPlatform: deps.verifyPlatform,
    openSource: deps.openSource,
    order: {
      sourceField: "barionPaymentSource",
      prepareSource: deps.prepareSource,
      readSource: (orderId, commandId) => rpc("source", { orderId, commandId }),
    },
  };
  return {
    ...binding,
    webhook: { handle: (request) => barionWebhook(request, binding, rpc) },
  };
}

/** Callback is unauthenticated routing only. Bind a known saved remote ID and
 * schedule a POSKey-authenticated read. Unknown IDs get the same acknowledgement.
 * Failed reads remain in the durable recovery queue, never accepted as money.
 */
export async function barionWebhook(
  request: Request,
  deps: PaymentDependencies,
  rpc: BarionDependencies["rpc"],
) {
  if (request.method !== "POST") {
    return new Response(null, { status: 405, headers: paymentHeaders });
  }
  try {
    await readPaymentBytes(request, 4096);
    const url = new URL(request.url),
      ids = url.searchParams.getAll("paymentId");
    if (ids.length !== 1) throw new PaymentError("barion_callback_invalid");
    const paymentId = barionId(ids[0]);
    // Durable scheduling before acknowledgement avoids an untracked background
    // promise and the provider's 15-second acknowledgement deadline.
    await rpc("callback_schedule", { paymentId });
    return new Response(null, { status: 200, headers: paymentHeaders });
  } catch {
    return new Response(null, { status: 400, headers: paymentHeaders });
  }
}
