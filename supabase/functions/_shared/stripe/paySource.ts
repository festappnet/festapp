import { preparePaymentSource, openPaymentSource } from "../payments/paySource.ts";
import { PaymentError } from "../payments/contracts.ts";
import { openEmail } from "../emailPayload.ts";
import { record, StripeBoundaryError } from "./provider.ts";
const encoder = new TextEncoder();
const hex = (bytes: Uint8Array) =>
  Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
async function hash(value: string) {
  return hex(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", encoder.encode(value)),
    ),
  );
}
export type PaymentSecrets = { payToken: string; returnHandle: string };
export function stripePrivatePayUrl(
  source: unknown,
  token: string,
  allowedOrigins: string[],
) {
  const url = new URL(String(record(source).payBaseUrl));
  if (
    url.protocol !== "https:" || url.username || url.password || url.search ||
    url.hash || !allowedOrigins.includes(url.origin) ||
    !url.pathname.endsWith("/stripe/pay") || !/^[a-f0-9]{64}$/.test(token)
  ) throw new StripeBoundaryError("stripe_payment_origin_invalid");
  url.hash = "pay=" + token;
  return url.toString();
}
export const prepareStripePaySource = preparePaymentSource;
export async function openStripePaySource(value: unknown, open = openEmail) {
  try { return await openPaymentSource(value, open); }
  catch (error) {
    if (error instanceof PaymentError && error.code === "payment_source_invalid")
      throw new StripeBoundaryError("stripe_payment_source_invalid");
    throw error;
  }
}

// One deterministic, scope-separated bearer for replay of the same creation.
export async function stripeHandoffToken(
  secrets: PaymentSecrets,
  orderId: number,
  commandId: string,
) {
  if (
    !Number.isSafeInteger(orderId) || orderId <= 0 ||
    !/^[a-f0-9-]{36}$/.test(commandId) ||
    !/^[a-f0-9]{64}$/.test(secrets.payToken)
  ) throw new StripeBoundaryError("stripe_handoff_invalid");
  return await hash(
    "festapp:handoff:v1:" + secrets.payToken + ":" + orderId + ":" + commandId,
  );
}
export function stripePrivateHandoffUrl(
  source: unknown,
  token: string,
  allowedOrigins: string[],
) {
  const url = new URL(stripePrivatePayUrl(source, token, allowedOrigins));
  url.hash = "handoff=" + token;
  return url.toString();
}
