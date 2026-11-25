import {
  type CheckoutSnapshot,
  type DispatchClaim,
  type HostedCheckoutConnector,
  type HostedPaymentDependencies,
  PaymentError,
} from "../payments/contracts.ts";
import { createRpcHostedPaymentStore } from "../payments/rpcHostedPaymentStore.ts";
import { paymentHeaders, readPaymentBytes } from "../payments/http.ts";
import { BarionSandboxProvider } from "./provider.ts";
import { barionFacts, barionId } from "./facts.ts";

export type BarionDependencies = {
  provider: BarionSandboxProvider;
  rpc(operation: string, args: Record<string, unknown>): Promise<unknown>;
  allowedOrigins: readonly string[];
  verifyPlatform(): Promise<void>;
  openSource: HostedPaymentDependencies["openSource"];
  prepareSource(): Promise<unknown>;
};
export class BarionPaymentConnector implements HostedCheckoutConnector {
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
): HostedPaymentDependencies {
  const rpc = deps.rpc;
  const binding: HostedPaymentDependencies = {
    livemode: false,
    allowedOrigins: deps.allowedOrigins,
    routes: {
      payPath: "/payments/barion/pay",
      returnPath: "/payments/barion/return",
    },
    connector: new BarionPaymentConnector(deps.provider),
    store: createRpcHostedPaymentStore("barion", rpc),
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
  deps: HostedPaymentDependencies,
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
