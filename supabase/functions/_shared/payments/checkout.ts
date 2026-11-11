import {
  type PaymentClaim,
  type DispatchClaim,
  type HostedPaymentDependencies,
  PaymentError,
  type ProviderEvent,
  record,
} from "./contracts.ts";

function fail(deps: HostedPaymentDependencies, suffix: string): never {
  throw new PaymentError(`${deps.connector.id}_${suffix}`, true);
}

async function preparedClaim(claim: PaymentClaim, deps: HostedPaymentDependencies, creation = false) {
  await deps.verifyPlatform();
  if (claim.providerId !== deps.connector.id || claim.disposition !== "dispatch" || claim.snapshot.livemode !== deps.livemode)
    fail(deps, "dispatch_invalid");
  let target: URL | undefined;
  if (creation) {
    const source = await deps.openSource(claim.source);
    target = new URL(claim.returnBaseUrl);
    if (!deps.allowedOrigins.includes(target.origin) || target.search || target.hash || target.username || target.password ||
        !target.pathname.endsWith(deps.routes.returnPath)) fail(deps, "return_origin_invalid");
    target.searchParams.set("return_handle", source.returnHandle);
  }
  return {claim: claim as DispatchClaim, snapshot: {...claim.snapshot, ...(target ? {returnUrl: target.toString()} : {})}, lease: claim.lease};
}

export async function synchronizePaymentClaim(
  value: PaymentClaim,
  event: ProviderEvent | null,
  deps: HostedPaymentDependencies,
  checkoutId?: string,
) {
  const { claim, snapshot, lease } = await preparedClaim(value, deps);
  const id = checkoutId ?? claim.checkoutId;
  if (typeof id !== "string") fail(deps, "checkout_identity_missing");
  const facts = await deps.connector.observePayment(
    snapshot,
    id,
    claim.connectorState,
  );
  if (
    facts.checkoutId !== id ||
    !["open", "complete", "expired"].includes(facts.checkoutStatus) ||
    [...facts.movements, ...facts.disputes].some((f) =>
      !Number.isSafeInteger(f.amountMinor) || f.amountMinor <= 0 ||
      f.currency !== snapshot.currency
    )
  ) fail(deps, "fact_mismatch");
  return (await deps.store.ingest(snapshot, lease, event, facts)).payment;
}

export async function checkoutPayment(
  token: string,
  deps: HostedPaymentDependencies,
): Promise<{ payment: Record<string, unknown>; checkoutUrl?: string }> {
  const claim = await deps.store.claimCheckout(token);
  if (claim.providerId !== deps.connector.id) fail(deps, "dispatch_invalid");
  if (claim.disposition === "read" || claim.disposition === "busy") {
    return { payment: claim.payment };
  }
  if (claim.disposition !== "dispatch") fail(deps, "dispatch_invalid");
  const { snapshot, lease } = await preparedClaim(
    claim,
    deps,
    !claim.checkoutId,
  );
  try {
    const checkout = claim.checkoutId
      ? await deps.connector.checkout(snapshot, claim.checkoutId)
      : await deps.connector.createOrRecoverCheckout(snapshot);
    if (
      !checkout.id || !Number.isSafeInteger(checkout.expiresAt) ||
      checkout.expiresAt > snapshot.expiresAt
    ) fail(deps, "checkout_identity_invalid");
    if (checkout.status !== "open") {
      return {
        payment: await synchronizePaymentClaim(claim, null, deps, checkout.id),
      };
    }
    if (!checkout.url) fail(deps, "checkout_url_missing");
    const url = deps.connector.validateCheckoutUrl(checkout.url);
    const receipt = await deps.store.commitCheckout(snapshot, lease, { ...checkout, url });
    if (receipt.committed !== true) fail(deps, "checkout_not_committed");
    const payment = record(receipt.payment);
    if (payment.method !== deps.connector.id) {
      fail(deps, "checkout_provider_mismatch");
    }
    return {
      payment,
      ...(payment.status === "open" ? { checkoutUrl: url } : {}),
    };
  } catch (error) {
    await deps.store.failCheckout(snapshot, lease).catch(() => {});
    throw error;
  }
}

/** Retry never chooses a new attempt, expiry, recipient or idempotency key. */
export async function recoverPaymentClaim(
  value: PaymentClaim,
  deps: HostedPaymentDependencies,
) {
  const { claim, snapshot, lease } = await preparedClaim(value, deps,
    deps.connector.recoveryRequiresSource !== false && value.disposition === "dispatch" && !value.checkoutId && Math.floor(Date.now()/1000) < value.snapshot.expiresAt);
  const result = await deps.connector.recoverCheckout(claim, snapshot);
  if (result.kind === "found") return await synchronizePaymentClaim(claim, null, deps, result.checkoutId);
  if (result.kind === "definitively_absent") {
    if (!result.evidence) fail(deps, "absence_evidence_missing");
    return (await deps.store.ingest(snapshot, lease, null, {
      checkoutId: null, paymentId: null, checkoutStatus: "expired", movements: [], disputes: [], noCheckoutVerified: true,
    })).payment;
  }
  if (!Number.isSafeInteger(result.retryAfterSeconds) || result.retryAfterSeconds < 1 || !result.reason) fail(deps, "recovery_invalid");
  if (!result.checkpointed) await deps.store.deferRecovery(claim, result);
  return {method: deps.connector.id, status: "pending", reconciliationPending: true};
}

export async function checkoutHandoff(
  token: string,
  deps: HostedPaymentDependencies,
  consume = true,
) {
  const result = record(await deps.store.readHandoff(token, consume));
  if (!consume) return { payment: record(result.payment) };
  const secrets = await deps.openSource(result.source);
  return await checkoutPayment(secrets.payToken, deps);
}
