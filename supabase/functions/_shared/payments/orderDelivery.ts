import { type HostedPaymentDependencies, PaymentError, record } from "./contracts.ts";
import { checkoutPayment } from "./checkout.ts";

async function hash(value: string) {
  return Array.from(
    new Uint8Array(
      await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
}

export async function prepareOrderDelivery(
  sourceValue: unknown,
  orderId: number,
  commandId: string,
  surface: unknown,
  fallbackPayment: unknown,
  deps: HostedPaymentDependencies,
): Promise<Record<string, unknown>> {
  const source = record(sourceValue);
  if (!source.sealed) return { payment: source.payment ?? fallbackPayment };
  const secrets = await deps.openSource(source);
  const embedded = surface === "embed";
  if (
    !Number.isSafeInteger(orderId) || orderId <= 0 ||
    !/^[a-f0-9-]{36}$/.test(commandId) ||
    !/^[a-f0-9]{64}$/.test(secrets.payToken)
  ) throw new PaymentError("payment_handoff_invalid");
  const token = embedded
    ? await hash(
      "festapp:handoff:v1:" + secrets.payToken + ":" + orderId + ":" +
        commandId,
    )
    : secrets.payToken;
  const url = new URL(String(source.payBaseUrl));
  if (
    url.protocol !== "https:" || url.username || url.password || url.search ||
    url.hash || !deps.allowedOrigins.includes(url.origin) ||
    !url.pathname.endsWith(deps.routes.payPath)
  ) throw new PaymentError("payment_origin_invalid");
  url.hash = `${embedded ? "handoff" : "pay"}=${token}`;
  if (embedded) {
    await deps.store.attachHandoff(orderId, commandId, await hash(token));
  }
  const result: Record<string, unknown> = {
    payment: source.payment ?? fallbackPayment,
    payment_access: {
      ...(embedded ? { kind: "handoff" } : {}),
      token,
      url: url.toString(),
    },
  };
  try {
    const prepared = await checkoutPayment(secrets.payToken, deps);
    result.payment = prepared.payment;
    if (!embedded && prepared.checkoutUrl) {
      result.checkout_url = prepared.checkoutUrl;
    }
  } catch {
    // The order is committed. Keep the same capability and attempt for recovery.
  }
  return result;
}
