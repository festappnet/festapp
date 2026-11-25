import {
  type CheckoutSnapshot,
  PaymentError,
  record,
} from "../payments/contracts.ts";

const gateway = "https://gw.sandbox.gopay.com";
const paymentStates = new Set([
  "CREATED",
  "PAYMENT_METHOD_CHOSEN",
  "PAID",
  "CANCELED",
  "TIMEOUTED",
  "PARTIALLY_REFUNDED",
  "REFUNDED",
]);

export function goPayId(value: unknown): string {
  if (typeof value === "number" && Number.isSafeInteger(value)) {
    value = String(value);
  }
  if (typeof value !== "string" || !/^[1-9][0-9]{0,15}$/.test(value)) {
    throw new PaymentError("gopay_identity_invalid", true);
  }
  return value;
}

export function validateGoPayCheckoutUrl(value: string): string {
  const url = new URL(value);
  if (
    url.origin !== gateway || url.username || url.password || url.search ||
    url.hash || !/^\/gw\/v3\/[A-Za-z0-9_-]+$/.test(url.pathname)
  ) {
    throw new PaymentError("gopay_checkout_url_invalid", true);
  }
  return url.href;
}

type Configuration = Readonly<{
  goId: string;
  clientId: string;
  clientSecret: string;
  storefrontOrigin: string;
  notificationUrl: string;
}>;

export class GoPaySandboxProvider {
  constructor(
    private readonly config: Configuration,
    private readonly fetcher: typeof fetch = fetch,
  ) {
    const origin = new URL(config.storefrontOrigin);
    const notification = new URL(config.notificationUrl);
    if (
      origin.protocol !== "https:" ||
      origin.origin !== config.storefrontOrigin ||
      notification.protocol !== "https:" || notification.username ||
      notification.password || notification.hash ||
      notification.searchParams.get("provider") !== "gopay" ||
      !/^[a-f0-9]{64}$/.test(notification.searchParams.get("hook") ?? "") ||
      notification.searchParams.getAll("hook").length !== 1 ||
      notification.searchParams.has("id") ||
      !/^[A-Za-z0-9_-]+$/.test(config.clientId) ||
      !/^[!-~]+$/.test(config.clientSecret) ||
      !Number.isSafeInteger(Number(goPayId(config.goId)))
    ) {
      throw new PaymentError("gopay_not_configured");
    }
  }

  async createPayment(snapshot: CheckoutSnapshot) {
    this.verifySnapshot(snapshot);
    const returnUrl = new URL(snapshot.returnUrl ?? "");
    if (
      returnUrl.origin !== this.config.storefrontOrigin ||
      returnUrl.pathname !== "/payments/gopay/return" || returnUrl.username ||
      returnUrl.password || returnUrl.hash
    ) throw new PaymentError("gopay_return_url_invalid");
    const body = {
      amount: snapshot.amountMinor,
      currency: snapshot.currency,
      order_number: this.orderNumber(snapshot),
      order_description: this.config.storefrontOrigin,
      target: { type: "ACCOUNT", goid: Number(this.config.goId) },
      payer: {
        default_payment_instrument: "PAYMENT_CARD",
        allowed_payment_instruments: ["PAYMENT_CARD"],
      },
      callback: {
        return_url: returnUrl.href,
        notification_url: this.config.notificationUrl,
      },
      lang: snapshot.locale === "auto"
        ? "CS"
        : (snapshot.locale ?? "cs").toUpperCase(),
    };
    const token = await this.token("payment-create");
    const response = await this.json("/payments/payment", {
      method: "POST",
      headers: {
        authorization: `Bearer ${token}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(body),
    });
    const payment = this.payment(snapshot, goPayId(response.id), response);
    if (payment.state !== "CREATED" || !payment.url) {
      throw new PaymentError("gopay_create_response_invalid", true);
    }
    return payment;
  }

  async paymentState(snapshot: CheckoutSnapshot, id: string) {
    this.verifySnapshot(snapshot);
    const token = await this.token("payment-all");
    const response = await this.json(`/payments/payment/${goPayId(id)}`, {
      headers: { authorization: `Bearer ${token}` },
    });
    return this.payment(snapshot, id, response);
  }

  private verifySnapshot(snapshot: CheckoutSnapshot) {
    if (
      snapshot.livemode || snapshot.accountId !== this.config.goId ||
      snapshot.currency !== "CZK"
    ) throw new PaymentError("gopay_scope_invalid");
  }

  private orderNumber(snapshot: CheckoutSnapshot) {
    return snapshot.attemptId.replaceAll("-", "");
  }

  private payment(
    snapshot: CheckoutSnapshot,
    id: string,
    response: Record<string, unknown>,
  ) {
    const target = record(response.target);
    const state = String(response.state);
    if (
      goPayId(response.id) !== id ||
      response.order_number !== this.orderNumber(snapshot) ||
      target.type !== "ACCOUNT" ||
      goPayId(target.goid) !== snapshot.accountId ||
      response.amount !== snapshot.amountMinor ||
      response.currency !== snapshot.currency || !paymentStates.has(state)
    ) throw new PaymentError("gopay_payment_mismatch", true);

    const url = typeof response.gw_url === "string"
      ? validateGoPayCheckoutUrl(response.gw_url)
      : null;
    return { id, state, url };
  }

  private async token(scope: "payment-all" | "payment-create") {
    const basic = btoa(`${this.config.clientId}:${this.config.clientSecret}`);
    const response = await this.json("/oauth2/token", {
      method: "POST",
      headers: {
        authorization: `Basic ${basic}`,
        "content-type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ grant_type: "client_credentials", scope }),
    });
    if (
      typeof response.access_token !== "string" ||
      !/^[A-Za-z0-9._~+/=-]+$/.test(response.access_token) ||
      String(response.token_type).toLowerCase() !== "bearer"
    ) throw new PaymentError("gopay_token_invalid", true);
    return response.access_token;
  }

  private async json(path: string, init: RequestInit) {
    try {
      const headers = new Headers(init.headers);
      headers.set("accept", "application/json");
      const response = await this.fetcher(`${gateway}/api${path}`, {
        ...init,
        headers,
        redirect: "error",
        signal: AbortSignal.timeout(8_000),
      });
      if (!response.ok) throw new Error();
      return record(await response.json());
    } catch {
      throw new PaymentError("gopay_request_failed", true);
    }
  }
}
