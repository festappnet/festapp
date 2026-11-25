import { timingSafeEqual } from "node:crypto";
import {
  type CheckoutSnapshot,
  type ConnectorState,
  type DispatchClaim,
  type HostedCheckoutConnector,
  type HostedPaymentDependencies,
  PaymentError,
  type PaymentObservation,
} from "../payments/contracts.ts";
import { paymentHeaders } from "../payments/http.ts";
import {
  createRpcHostedPaymentStore,
  type HostedPaymentRpc,
} from "../payments/rpcHostedPaymentStore.ts";
import {
  goPayId,
  GoPaySandboxProvider,
  validateGoPayCheckoutUrl,
} from "./provider.ts";

export class GoPayPaymentConnector implements HostedCheckoutConnector {
  readonly id = "gopay";
  readonly displayName = "GoPay sandbox";
  readonly recoveryRequiresSource = false;
  readonly validateCheckoutUrl = validateGoPayCheckoutUrl;

  constructor(
    private readonly provider: GoPaySandboxProvider,
    private readonly now = () => Math.ceil(Date.now() / 1000),
  ) {}

  async createOrRecoverCheckout(snapshot: CheckoutSnapshot) {
    const payment = await this.provider.createPayment(snapshot);
    return {
      id: payment.id,
      url: payment.url,
      status: "open" as const,
      expiresAt: snapshot.expiresAt,
    };
  }

  async checkout(snapshot: CheckoutSnapshot, id: string) {
    const payment = await this.provider.paymentState(snapshot, id);
    const status = this.checkoutStatus(payment.state);
    // A pending card authorization must never reopen the payment form.
    return {
      id,
      url: payment.state === "CREATED" ? payment.url : null,
      status,
      expiresAt: snapshot.expiresAt,
    };
  }

  recoverCheckout(claim: DispatchClaim) {
    // The public API offers reads by GoPay ID, with no documented deduplication
    // guarantee for create. A lost create response cannot authorize a retry.
    return Promise.resolve(
      claim.checkoutId
        ? { kind: "found" as const, checkoutId: claim.checkoutId }
        : {
          kind: "unresolved" as const,
          reason: "gopay_payment_id_unknown",
          retryAfterSeconds: 120,
        },
    );
  }

  async observePayment(
    snapshot: CheckoutSnapshot,
    id: string,
    saved: ConnectorState,
  ): Promise<PaymentObservation> {
    const payment = await this.provider.paymentState(snapshot, id);
    const refunded = payment.state === "REFUNDED" ||
      payment.state === "PARTIALLY_REFUNDED";
    const paid = payment.state === "PAID" || refunded;
    // Status inquiry has no settlement timestamp. Use the first verified
    // observation as an upper bound and retain that time across subsequent reads.
    const occurredAt = saved.paidObservedAt == null
      ? this.now()
      : Number(saved.paidObservedAt);
    if (
      paid &&
      (!Number.isSafeInteger(occurredAt) || occurredAt < snapshot.createdAt)
    ) {
      throw new PaymentError("gopay_payment_time_invalid", true);
    }

    return {
      checkoutId: id,
      paymentId: id,
      checkoutStatus: this.checkoutStatus(payment.state),
      connectorState: { goPayState: payment.state },
      movements: paid
        ? [{
          providerId: id,
          kind: "payment",
          amountMinor: snapshot.amountMinor,
          currency: snapshot.currency,
          occurredAt,
        }]
        : [],
      // The sandbox will hold admission on confirmed refund states until a
      // real refund-history response verifies independent amount/ID semantics.
      disputes: refunded
        ? [{
          providerId: id,
          amountMinor: snapshot.amountMinor,
          currency: snapshot.currency,
          status: payment.state,
          hold: true,
        }]
        : [],
    };
  }

  private checkoutStatus(state: string): PaymentObservation["checkoutStatus"] {
    if (state === "CANCELED" || state === "TIMEOUTED") return "expired";
    if (state === "CREATED") return "open";
    return "complete";
  }
}

type Dependencies = Readonly<{
  provider: GoPaySandboxProvider;
  rpc: HostedPaymentRpc;
  storefrontOrigin: string;
  callbackToken: string;
  openSource: HostedPaymentDependencies["openSource"];
  prepareSource(): Promise<unknown>;
}>;

export function goPayPaymentAdapter(
  deps: Dependencies,
): HostedPaymentDependencies {
  return {
    livemode: false,
    allowedOrigins: [deps.storefrontOrigin],
    routes: {
      payPath: "/payments/gopay/pay",
      returnPath: "/payments/gopay/return",
    },
    connector: new GoPayPaymentConnector(deps.provider),
    store: createRpcHostedPaymentStore("gopay", deps.rpc),
    verifyPlatform: () => Promise.resolve(),
    openSource: deps.openSource,
    order: {
      sourceField: "goPayPaymentSource",
      prepareSource: deps.prepareSource,
      readSource: (orderId, commandId) =>
        deps.rpc("source", { orderId, commandId }),
    },
    webhook: {
      handle: (request) => goPayWebhook(request, deps.rpc, deps.callbackToken),
    },
  };
}

export async function goPayWebhook(
  request: Request,
  rpc: HostedPaymentRpc,
  callbackToken: string,
) {
  if (request.method !== "GET") {
    return new Response(null, { status: 405, headers: paymentHeaders });
  }
  let paymentId: string;
  try {
    const query = new URL(request.url).searchParams;
    const supplied = query.getAll("hook");
    const encoder = new TextEncoder();
    if (
      supplied.length !== 1 || !/^[a-f0-9]{64}$/.test(supplied[0]) ||
      !/^[a-f0-9]{64}$/.test(callbackToken) ||
      !timingSafeEqual(
        encoder.encode(supplied[0]),
        encoder.encode(callbackToken),
      )
    ) return new Response(null, { status: 403, headers: paymentHeaders });
    const ids = query.getAll("id");
    if (ids.length !== 1 || query.has("parent_id")) throw new Error();
    paymentId = goPayId(ids[0]);
  } catch {
    return new Response(null, { status: 400, headers: paymentHeaders });
  }
  try {
    // A callback schedules an authenticated read only for an already bound ID.
    await rpc("callback_schedule", { paymentId });
    return new Response(null, { status: 200, headers: paymentHeaders });
  } catch {
    return new Response(null, { status: 503, headers: paymentHeaders });
  }
}
