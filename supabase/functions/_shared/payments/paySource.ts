import { openEmail, sealEmail } from "../emailPayload.ts";
import { PaymentError, type PaymentSecrets, record } from "./contracts.ts";
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
export async function preparePaymentSource(seal = sealEmail) {
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
export async function openPaymentSource(value: unknown, open = openEmail) {
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
    throw new PaymentError("payment_source_invalid");
  }
  return secrets as PaymentSecrets;
}
