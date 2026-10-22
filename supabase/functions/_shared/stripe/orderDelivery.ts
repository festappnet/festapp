import { record } from "./provider.ts";
import {
  openStripePaySource,
  stripeHandoffToken,
  stripePrivateHandoffUrl,
  stripePrivatePayUrl,
} from "./paySource.ts";
import {
  checkoutStripePayment,
  type StripePaymentsDependencies,
} from "./payments.ts";

/** Prepare Checkout within the fixed dispatch window, before returning either
 * delivery surface. An iframe receives only its one-use handoff, never Checkout
 * or order_pay. Delayed manual opening then resumes an already prepared Session.
 */
export async function prepareStripeOrderDelivery(
  sourceValue: unknown,
  orderId: number,
  commandId: string,
  surface: unknown,
  fallbackPayment: unknown,
  deps: StripePaymentsDependencies,
): Promise<Record<string, unknown>> {
  const source = record(sourceValue);
  if (!source.sealed) return { payment: source.payment ?? fallbackPayment };
  const secrets = await (deps.openSource ?? openStripePaySource)(source);
  const embedded = surface === "embed";
  const token = embedded
    ? await stripeHandoffToken(secrets, orderId, commandId)
    : secrets.payToken;
  const url = embedded
    ? stripePrivateHandoffUrl(source, token, deps.allowedOrigins)
    : stripePrivatePayUrl(source, token, deps.allowedOrigins);
  if (embedded) {
    const digest = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(token),
    );
    const tokenHash = Array.from(
      new Uint8Array(digest),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    await deps.rpc("attach_stripe_handoff_internal", {
      p_order: orderId,
      p_command: commandId,
      p_token_hash: tokenHash,
      p_livemode: deps.livemode,
    });
  }
  const result: Record<string, unknown> = {
    payment: source.payment ?? fallbackPayment,
    payment_access: { ...(embedded ? { kind: "handoff" } : {}), token, url },
  };
  try {
    const prepared = await checkoutStripePayment(secrets.payToken, deps);
    result.payment = prepared.payment;
    if (!embedded && prepared.checkoutUrl) {
      result.checkout_url = prepared.checkoutUrl;
    }
  } catch {
    // Creation is already committed. Preserve its capability and attempt; the
    // recovery worker resolves uncertainty without a second order or new key.
  }
  return result;
}
