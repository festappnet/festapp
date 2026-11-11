/** The payment engine knows no provider objects, SDKs, URLs or RPC names.
 * A connector verifies external facts; its store binds them to saved attempts.
 */
export class PaymentError extends Error {
  constructor(public readonly code: string, public readonly retryable = false) {
    super(code);
    this.name = "PaymentError";
  }
}

export function record(value: unknown): Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

export type CheckoutSnapshot = Readonly<{
  attemptId: string;
  accountId: string;
  livemode: boolean;
  amountMinor: number;
  currency: string;
  orderReference: string;
  expiresAt: number;
  createdAt: number;
  idempotencyKey: string;
  returnUrl?: string;
  locale?: "auto" | "cs" | "en" | "de" | "pl" | "sk";
}>;

export type Checkout = Readonly<{
  id: string;
  status: "open" | "complete" | "expired";
  url: string | null;
  expiresAt: number;
}>;

export type Movement = Readonly<{
  providerId: string;
  kind: "payment" | "refund";
  amountMinor: number;
  currency: string;
  occurredAt: number;
}>;

export type Dispute = Readonly<{
  providerId: string;
  amountMinor: number;
  currency: string;
  status: string;
  hold: boolean;
}>;

export type PaymentObservation = Readonly<{
  checkoutId: string | null;
  paymentId: string | null;
  checkoutStatus: "open" | "complete" | "expired";
  movements: readonly Movement[];
  disputes: readonly Dispute[];
  connectorState?: ConnectorState;
  noCheckoutVerified?: boolean;
}>;

export type PaymentSecrets = { payToken: string; returnHandle: string };
export type PaymentView = Record<string, unknown>;
export type PaymentHandoff = Readonly<{payment?: PaymentView; source?: unknown}>;
export type ConnectorState = Readonly<Record<string, string | null>>;
export type PaymentClaim = Readonly<{ providerId: string }> & (
  | Readonly<{ disposition: "read" | "busy"; payment: PaymentView }>
  | Readonly<{ disposition: "dispatch"; lease: string; snapshot: CheckoutSnapshot;
      returnBaseUrl: string; checkoutId: string | null; connectorState: ConnectorState; source: unknown }>
);
export type DispatchClaim = Extract<PaymentClaim, { disposition: "dispatch" }>;
export type CommitReceipt = Readonly<{ committed: true; payment: PaymentView }>;
export type RecoveryResult =
  | Readonly<{ kind: "found"; checkoutId: string }>
  | Readonly<{ kind: "definitively_absent"; evidence: string }>
  | Readonly<{ kind: "unresolved"; reason: string; retryAfterSeconds: number; checkpointed?: boolean }>;
export type RecoveryAttempt = Readonly<{ attemptId: string; accountId: string }>;
export type RecoveryConnection = Readonly<{ connectionId: string; accountId: string }>;

/** Decode untrusted RPC JSON once at the connector boundary. */
export function decodePaymentClaim(value: unknown, providerId: string): PaymentClaim {
  const c = record(value), s = record(c.snapshot);
  const invalid = () => { throw new PaymentError(`${providerId}_dispatch_invalid`); };
  if (c.providerId !== providerId) invalid();
  if (c.disposition === "read" || c.disposition === "busy") {
    if (record(c.payment).method !== providerId || typeof record(c.payment).status !== "string") invalid();
    return {providerId, disposition: c.disposition, payment: record(c.payment)};
  }
  if (c.disposition !== "dispatch" || typeof c.lease !== "string" || !c.lease ||
      typeof s.attemptId !== "string" || !s.attemptId || typeof s.accountId !== "string" || !s.accountId ||
      typeof s.livemode !== "boolean" || !Number.isSafeInteger(s.amountMinor) || Number(s.amountMinor) <= 0 ||
      typeof s.currency !== "string" || !/^[A-Z]{3}$/.test(s.currency) ||
      typeof s.orderReference !== "string" || !Number.isSafeInteger(s.createdAt) ||
      !Number.isSafeInteger(s.expiresAt) || Number(s.expiresAt) <= Number(s.createdAt) ||
      typeof s.idempotencyKey !== "string" || s.idempotencyKey.length < 8 || s.idempotencyKey.length > 255 ||
      typeof c.returnBaseUrl !== "string" || (c.checkoutId !== null && typeof c.checkoutId !== "string") ||
      !c.connectorState || typeof c.connectorState !== "object" || Array.isArray(c.connectorState) ||
      Object.values(record(c.connectorState)).some(v => v !== null && typeof v !== "string")) invalid();
  if (s.locale != null && !["auto","cs","en","de","pl","sk"].includes(String(s.locale))) invalid();
  return {providerId, disposition: "dispatch", lease: c.lease as string,
    snapshot: {attemptId: s.attemptId as string, accountId: s.accountId as string, livemode: s.livemode as boolean,
      amountMinor: s.amountMinor as number, currency: s.currency as string, orderReference: s.orderReference as string,
      createdAt: s.createdAt as number, expiresAt: s.expiresAt as number, idempotencyKey: s.idempotencyKey as string,
      locale: (s.locale ?? undefined) as CheckoutSnapshot["locale"]}, returnBaseUrl: c.returnBaseUrl as string,
    checkoutId: c.checkoutId as string | null, connectorState: c.connectorState as ConnectorState, source: c.source};
}
export function decodeCommitReceipt(value: unknown, providerId: string): CommitReceipt {
  const receipt = record(value), payment = record(receipt.payment);
  if (receipt.committed !== true || payment.method !== providerId || typeof payment.status !== "string")
    throw new PaymentError(`${providerId}_commit_receipt_invalid`, true);
  return {committed: true, payment};
}
export type ProviderEvent = Record<string, unknown>;

export interface HostedCheckoutConnector extends PaymentConnector {
  readonly id: string;
  readonly displayName: string;
  /** False for protocols whose recovery is read-only and never needs bearer secrets. */
  readonly recoveryRequiresSource?: boolean;
  /** This policy is executable: never trust a provider URL or client redirect. */
  validateCheckoutUrl(value: string): string;
  createOrRecoverCheckout(snapshot: CheckoutSnapshot): Promise<Checkout>;
  checkout(snapshot: CheckoutSnapshot, id: string): Promise<Checkout>;
  recoverCheckout(claim: DispatchClaim, snapshot: CheckoutSnapshot): Promise<RecoveryResult>;
  /** Always reads current verified provider state, never a browser-return flag. */
  observePayment(
    snapshot: CheckoutSnapshot,
    checkoutId: string,
    state: ConnectorState,
  ): Promise<PaymentObservation>;
}

/** Persistence is part of a connector's implementation, not the engine's API.
 * Stores must preserve tenant/account/mode identity, leases and atomic ingestion.
 * All settlement effects end in the existing SQL order/ticket lifecycle.
 */
export interface PaymentStore {
  claimCheckout(token: string): Promise<PaymentClaim>;
  commitCheckout(
    snapshot: CheckoutSnapshot,
    lease: string,
    checkout: Checkout,
  ): Promise<CommitReceipt>;
  failCheckout(snapshot: CheckoutSnapshot, lease: string): Promise<void>;
  ingest(
    snapshot: CheckoutSnapshot,
    lease: string,
    event: ProviderEvent | null,
    observation: PaymentObservation,
  ): Promise<CommitReceipt>;
  deferRecovery(claim: DispatchClaim, result: Extract<RecoveryResult, {kind: "unresolved"}>): Promise<void>;
  readReturn(token: string): Promise<PaymentView>;
  readStatus(token: string): Promise<PaymentView>;
  readHandoff(token: string, consume: boolean): Promise<PaymentHandoff>;
  attachHandoff(
    orderId: number,
    commandId: string,
    tokenHash: string,
  ): Promise<void>;
  purgeExpiredSources(): Promise<number>;
  recoverableAttempts(): Promise<readonly RecoveryAttempt[]>;
  claimSync(attempt: RecoveryAttempt): Promise<PaymentClaim>;
  failSync(attemptId: string, lease: string): Promise<void>;
}

export type HostedPaymentDependencies = Readonly<{
  livemode: boolean;
  allowedOrigins: readonly string[];
  routes: Readonly<{ payPath: string; returnPath: string }>;
  connector: HostedCheckoutConnector;
  store: PaymentStore;
  maintenance?: Readonly<{
    recoverableConnections(): Promise<readonly RecoveryConnection[]>;
    observeConnection(accountId: string): Promise<void>;
  }>;
  verifyPlatform(): Promise<void>;
  openSource(value: unknown): Promise<PaymentSecrets>;
  order?: Readonly<{
    sourceField: string;
    prepareSource(): Promise<unknown>;
    readSource(orderId: number, commandId: string): Promise<unknown>;
  }>;
  connection?: Readonly<{ handle(request: Request): Promise<Response> }>;
  webhook?: Readonly<{ handle(request: Request): Promise<Response> }>;
}>;

/** Shared identity. Hosted checkout is one optional capability, never a
 * requirement for ledger-backed methods. SQL remains installation authority. */
export interface PaymentConnector {
  readonly id: string;
  readonly displayName: string;
}
export type PaymentConfirmation = "local_commit" | "bank_event" | "verified_provider_observation";
export type PaymentOperationResult = Readonly<{
  kind: "recorded" | "show_bank_instructions" | "processing" | "unavailable";
  reason?: string;
  data?: Record<string, unknown>;
}>;
export type RefundSnapshot = Readonly<{
  requestId: string;
  attemptId: string;
  providerId: string;
  accountId: string;
  livemode: boolean;
  paymentId: string;
  amountMinor: number;
  currency: string;
  createdAt: number;
  idempotencyKey: string;
}>;
export type RefundObservation = Readonly<{
  status: "pending" | "action_required" | "succeeded" | "failed" | "cancelled" | "unknown";
  refundId?: string;
  amountMinor?: number;
  currency?: string;
  dispatchUncertain: boolean;
  connectorState?: ConnectorState;
}>;
export interface RefundCapability {
  readonly confirmation: PaymentConfirmation;
  readonly currencies: readonly string[];
  requestRefund(snapshot: RefundSnapshot): Promise<RefundObservation>;
  /** Recovery is read-only; absence in a list never authorizes another write. */
  recoverRefund(snapshot: RefundSnapshot, state: ConnectorState): Promise<RefundObservation>;
}
export type PaymentMethodBinding = Readonly<{
  connector: PaymentConnector;
  hostedCheckout?: HostedPaymentDependencies;
  refund?: RefundCapability;
  operation?: Readonly<{
    confirmation: PaymentConfirmation;
    execute(input: Record<string, unknown>, commandId: string, authorization: string): Promise<PaymentOperationResult>;
  }>;
}>;
export function hostedPaymentBinding(deps: HostedPaymentDependencies, refund?: RefundCapability): PaymentMethodBinding {
  return {connector: deps.connector, hostedCheckout: deps, ...(refund ? {refund} : {})};
}
export function requireHostedPayment(binding: PaymentMethodBinding): HostedPaymentDependencies {
  if (!binding.hostedCheckout || binding.hostedCheckout.connector.id !== binding.connector.id)
    throw new PaymentError("payment_hosted_checkout_unavailable");
  return binding.hostedCheckout;
}
