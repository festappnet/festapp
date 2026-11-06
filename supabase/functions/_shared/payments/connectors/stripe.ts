import type {
  Checkout,
  ConnectorState,
  DispatchClaim,
  RecoveryResult,
  RecoveryAttempt,
  RecoveryConnection,
  CheckoutSnapshot,
  PaymentConnector,
  PaymentDependencies,
  PaymentObservation,
  PaymentStore,
} from "../contracts.ts";
import {decodePaymentClaim, decodeCommitReceipt, PaymentError} from "../contracts.ts";
import {
  record,
  StripeBoundaryError,
  type StripeProvider,
} from "../../stripe/provider.ts";
import { disputeFact, paymentFact, refundFact } from "../../stripe/facts.ts";
import { observeStripeConnection } from "../../stripe/connectionStatus.ts";
import {
  openStripePaySource,
  prepareStripePaySource,
} from "../../stripe/paySource.ts";

export type StripePaymentsDependencies = {
  livemode: boolean;
  allowedOrigins: string[];
  webhookSecrets: string[];
  verifyPlatform(): Promise<void>;
  provider: Pick<
    StripeProvider,
    | "createOrRecoverSession"
    | "session"
    | "sessionCandidates"
    | "refunds"
    | "disputes"
    | "account"
  >;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
  openSource?: typeof openStripePaySource;
};

export function stripeClaim(value: unknown) {
  const c = record(value), s = record(c.snapshot);
  return decodePaymentClaim({...c, providerId: "stripe", checkoutId: s.sessionId ?? null,
    returnBaseUrl: s.returnBaseUrl, connectorState: {
      refundCursor: s.refundCursor ?? null, sessionLookupCursor: s.sessionLookupCursor ?? null,
      sessionLookupFound: s.sessionLookupFound ?? null,
    }}, "stripe");
}

function checkout(value: Record<string, unknown>): Checkout {
  if (
    typeof value.id !== "string" ||
    !["open", "complete", "expired"].includes(String(value.status)) ||
    !Number.isSafeInteger(value.expires_at)
  ) {
    throw new StripeBoundaryError("provider_response_invalid");
  }
  return {
    id: value.id,
    status: value.status as Checkout["status"],
    url: typeof value.url === "string" ? value.url : null,
    expiresAt: value.expires_at as number,
  };
}

/** All Stripe SDK shapes and financial verification live in this connector. */
export class StripePaymentConnector implements PaymentConnector {
  readonly id = "stripe";
  readonly displayName = "Stripe";
  constructor(
    private readonly provider: StripePaymentsDependencies["provider"],
    private readonly rpc: StripePaymentsDependencies["rpc"],
  ) {}
  validateCheckoutUrl(value: string) {
    const url = new URL(value);
    if (
      url.protocol !== "https:" || url.hostname !== "checkout.stripe.com" ||
      url.username || url.password || url.port
    ) throw new StripeBoundaryError("provider_response_invalid");
    return url.toString();
  }
  async createOrRecoverCheckout(snapshot: CheckoutSnapshot) {
    return checkout(await this.provider.createOrRecoverSession(snapshot));
  }
  async checkout(snapshot: CheckoutSnapshot, id: string) {
    return checkout(await this.provider.session(snapshot, id));
  }
  async recoverCheckout(claim: DispatchClaim, snapshot: CheckoutSnapshot): Promise<RecoveryResult> {
    if (claim.checkoutId) return {kind: "found", checkoutId: claim.checkoutId};
    const now = Math.floor(Date.now()/1000);
    if (now < snapshot.expiresAt && now - snapshot.createdAt < 23 * 3600) {
      return {kind: "found", checkoutId: (await this.createOrRecoverCheckout(snapshot)).id};
    }
    const state = claim.connectorState;
    const page = await this.provider.sessionCandidates(snapshot, state.sessionLookupCursor ?? undefined);
    const matches = new Set(page.matches);
    if (state.sessionLookupFound) matches.add(state.sessionLookupFound);
    if (matches.size > 1) throw new PaymentError("stripe_multiple_sessions_require_resolution", true);
    const found = [...matches][0] ?? null;
    if (page.nextCursor) {
      await this.rpc("checkpoint_stripe_session_lookup_internal", {p_attempt: snapshot.attemptId,
        p_lease: claim.lease, p_cursor: page.nextCursor, p_found: found});
      return {kind: "unresolved", reason: "lookup_incomplete", retryAfterSeconds: 10, checkpointed: true};
    }
    if (found) return {kind: "found", checkoutId: found};
    // The API list contract has no documented strongly consistent absence guarantee.
    return {kind: "unresolved", reason: "absence_not_proven", retryAfterSeconds: 120};
  }
  async observePayment(
    snapshot: CheckoutSnapshot,
    id: string,
    state: ConnectorState = {},
  ): Promise<PaymentObservation> {
    const session = await this.provider.session(snapshot, id);
    const payment = paymentFact(snapshot, session);
    const movements = payment ? [payment] : [];
    const intent = typeof session.payment_intent === "string"
      ? session.payment_intent
      : record(session.payment_intent).id;
    let refundCursor: string | null = null;
    let disputes: PaymentObservation["disputes"] = [];
    if (payment) {
      const refunds = await this.provider.refunds(
        snapshot,
        intent as string,
        state.refundCursor ?? undefined,
      );
      for (const refund of refunds.data) {
        const fact = refundFact(snapshot, intent as string, refund);
        if (fact) movements.push(fact);
      }
      refundCursor = refunds.nextCursor;
      if (!refundCursor) {
        disputes = (await this.provider.disputes(snapshot, intent as string))
          .map((d) => disputeFact(snapshot, intent as string, d));
      }
    }
    return {
      checkoutId: session.id as string,
      paymentId: typeof intent === "string" ? intent : null,
      checkoutStatus: session.status as Checkout["status"],
      movements,
      disputes,
      connectorState: {refundCursor},
    };
  }
}

/** Existing SQL objects are Stripe connector storage. Their names and wire
 * format are confined here, so adding a connector never adds RPC branches to
 * the payment engine. SQL remains the authority for settlement and admission.
 */
export function stripePaymentStore(
  deps: StripePaymentsDependencies,
): PaymentStore {
  const rpc = deps.rpc, mode = { p_livemode: deps.livemode };
  const commit = async (value: Promise<unknown>, wrapped = false) => {
    const result = await value;
    return decodeCommitReceipt(wrapped ? record(result).data : result, "stripe");
  };
  return {
    claimCheckout: async (token) =>
      stripeClaim(
        await rpc("claim_stripe_checkout_internal", {
          p_token: token,
          ...mode,
        }),
      ),
    commitCheckout: (s, lease, c) =>
      commit(rpc("commit_stripe_checkout_session_internal", {
        p_attempt: s.attemptId,
        p_lease: lease,
        p_session: c.id,
        p_url: c.url,
        p_expires: c.expiresAt,
      })),
    failCheckout: async (s, lease) => {
      await rpc("fail_stripe_checkout_internal", {
        p_attempt: s.attemptId,
        p_lease: lease,
      });
    },
    ingest: (s, lease, event, facts) =>
      commit(rpc("ingest_stripe_payment_internal", {
        p_attempt: s.attemptId,
        p_lease: lease,
        p_event: event ?? {
          id: "evt_reconcile" + crypto.randomUUID().replaceAll("-", ""),
          bodyHash: "0".repeat(64),
          accountId: s.accountId,
          livemode: s.livemode,
          type: "festapp.reconcile",
          created: Math.floor(Date.now() / 1000),
        },
        p_facts: {
          observedAt: new Date().toISOString(),
          sessionId: facts.checkoutId,
          paymentIntentId: facts.paymentId,
          sessionStatus: facts.checkoutStatus,
          movements: facts.movements,
          disputes: facts.disputes,
          ...(facts.connectorState?.refundCursor !== undefined
            ? { refundCursor: facts.connectorState!.refundCursor }
            : {}),
          ...(facts.noCheckoutVerified ? { noSessionVerified: true } : {}),
        },
      }), true),
    deferRecovery: async (claim, result) => {
      await rpc("defer_stripe_recovery_internal", {p_attempt: claim.snapshot.attemptId,
        p_lease: claim.lease, p_retry_seconds: result.retryAfterSeconds});
    },
    readReturn: async (token) =>
      decodeView(await rpc("read_stripe_return_internal", { p_token: token, ...mode })),
    readStatus: async (token) =>
      decodeView(await rpc("read_stripe_pay_status_internal", { p_token: token, ...mode })),
    readHandoff: async (token, consume) => {
      const value = record(await rpc("read_stripe_handoff_internal", {p_token: token, p_consume: consume, ...mode}));
      if (consume) {
        if (!value.source || typeof value.source !== "object") throw new PaymentError("stripe_handoff_invalid");
        return {source: value.source};
      }
      return {payment: decodeView(value.payment)};
    },
    attachHandoff: async (orderId, commandId, tokenHash) => {
      await rpc("attach_stripe_handoff_internal", {p_order: orderId, p_command: commandId, p_token_hash: tokenHash, ...mode});
    },
    purgeExpiredSources: async () => {
      const value = await rpc("purge_expired_stripe_sources_internal", {p_limit: 100});
      if (!Number.isSafeInteger(value) || Number(value) < 0 || Number(value) > 100) throw new PaymentError("stripe_recovery_invalid");
      return value as number;
    },
    recoverableAttempts: async () => decodeRecoveryRows<RecoveryAttempt>(
      await rpc("get_recoverable_stripe_attempts_internal", {...mode, p_limit: 10}), "attemptId", 10),
    claimSync: async (item) =>
      stripeClaim(
        await rpc("claim_stripe_sync_internal", {
          p_account: item.accountId,
          p_attempt: item.attemptId,
          ...mode,
        }),
      ),
    failSync: async (attemptId, lease) => {
      await rpc("fail_stripe_reconciliation_internal", {
        p_attempt: attemptId,
        p_lease: lease,
      });
    },
  };
}

export function stripePaymentAdapter(
  deps: StripePaymentsDependencies,
): PaymentDependencies {
  return {
    livemode: deps.livemode,
    allowedOrigins: deps.allowedOrigins,
    routes: { payPath: "/stripe/pay", returnPath: "/stripe/return" },
    connector: new StripePaymentConnector(deps.provider, deps.rpc),
    store: stripePaymentStore(deps),
    maintenance: {
      recoverableConnections: async () => decodeRecoveryRows<RecoveryConnection>(
        await deps.rpc("get_recoverable_stripe_connections_internal", {p_livemode: deps.livemode}), "connectionId", 2),
      observeConnection: async (accountId) => { await observeStripeConnection(accountId, deps); },
    },
    verifyPlatform: deps.verifyPlatform,
    openSource: deps.openSource ?? openStripePaySource,
    order: {
      sourceField: "stripePaymentSource",
      prepareSource: () => prepareStripePaySource(),
      readSource: (orderId, commandId) =>
        deps.rpc("get_stripe_order_pay_source_internal", {
          p_order: orderId,
          p_command: commandId,
        }),
    },
  };
}

function decodeRecoveryRows<T>(value: unknown, key: string, limit: number): readonly T[] {
  if (!Array.isArray(value) || value.length > limit || value.some(v => {
    const row = record(v); return typeof row[key] !== "string" || typeof row.accountId !== "string";
  })) throw new PaymentError("stripe_recovery_invalid");
  return value as T[];
}

function decodeView(value: unknown) {
  const view = record(value);
  if (view.method !== "stripe" || typeof view.status !== "string") throw new PaymentError("stripe_payment_view_invalid");
  return view;
}
