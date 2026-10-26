import { openEmail, sealEmail } from "../emailPayload.ts";
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
export async function prepareStripePaySource(seal = sealEmail) {
  const secrets: PaymentSecrets = {
    payToken: hex(crypto.getRandomValues(new Uint8Array(32))),
    returnHandle: hex(crypto.getRandomValues(new Uint8Array(32))),
  };
  return {
    tokenHash: await hash(secrets.payToken),
    returnHash: await hash(secrets.returnHandle),
    contentHash: await hash(JSON.stringify(secrets)),
    sealed: await seal(secrets),
  };
}
export async function openStripePaySource(value: unknown, open = openEmail) {
  const source = record(value);
  const secrets = record(
    await open(record(source.sealed) as Record<string, string>),
  );
  if (
    typeof secrets.payToken !== "string" ||
    !/^[a-f0-9]{64}$/.test(secrets.payToken) ||
    typeof secrets.returnHandle !== "string" ||
    !/^[a-f0-9]{64}$/.test(secrets.returnHandle) ||
    secrets.payToken === secrets.returnHandle ||
    await hash(secrets.payToken) !== source.tokenHash ||
    await hash(JSON.stringify(secrets)) !== source.contentHash
  ) {
    throw new StripeBoundaryError("stripe_payment_source_invalid");
  }
  return secrets as PaymentSecrets;
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
