import {
  type CheckoutSnapshot,
  PaymentError,
  record,
} from "../payments/contracts.ts";

const uuid =
  /^(?:[0-9a-f]{32}|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i;
const reject = (): never => {
  throw new PaymentError("barion_response_invalid", true);
};
export type BarionSandboxConfiguration = Readonly<{
  /** An operator-owned connection identity, never derived from a browser request. */
  accountId: string;
  posKey: string;
  payee: string;
  callbackUrl: string;
  allowedReturnOrigins: readonly string[];
  fetch?: typeof fetch;
}>;
/** Safe operator diagnostics; provider descriptions and bodies never escape. */
export class BarionRequestError extends PaymentError {
  readonly httpStatus: number;
  readonly providerCode: string | null;
  constructor(httpStatus: number, providerCode: unknown) {
    super("barion_remote_rejected", httpStatus === 429 || httpStatus >= 500);
    this.httpStatus = httpStatus;
    this.providerCode = typeof providerCode === "string" &&
        /^[A-Za-z][A-Za-z0-9_]{0,63}$/.test(providerCode) &&
        !/^[a-f0-9]{32}$/i.test(providerCode)
      ? providerCode
      : null;
  }
}
export type BarionCheckout = Readonly<
  { id: string; url: string; status: string }
>;

/** Sandbox protocol only. No live origin, automatic create retry, ticket rules,
 * credential discovery or claims of marketplace/chargeback support.
 */
export class BarionSandboxProvider {
  readonly #configuration: BarionSandboxConfiguration;
  readonly #fetch: typeof fetch;
  constructor(configuration: BarionSandboxConfiguration) {
    if (
      !configuration.accountId || !uuid.test(configuration.posKey) ||
      !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(configuration.payee)
    ) {
      throw new PaymentError("barion_not_configured");
    }
    const callback = new URL(configuration.callbackUrl);
    if (
      callback.protocol !== "https:" || callback.username ||
      callback.password || callback.hash
    ) {
      throw new PaymentError("barion_callback_invalid");
    }
    this.#configuration = configuration;
    this.#fetch = configuration.fetch ?? fetch;
  }
  validateCheckoutUrl(value: string): string {
    const url = new URL(value);
    const keys = [...url.searchParams.keys()];
    if (
      url.protocol !== "https:" || url.hostname !== "secure.test.barion.com" ||
      url.port || url.username || url.password ||
      url.pathname.toLowerCase() !== "/pay" ||
      keys.length !== 1 || keys[0].toLowerCase() !== "id" ||
      !uuid.test(url.searchParams.get(keys[0]) ?? "") || url.hash
    ) reject();
    return url.toString();
  }
  #validate(snapshot: CheckoutSnapshot) {
    if (
      snapshot.livemode ||
      snapshot.accountId !== this.#configuration.accountId ||
      !uuid.test(snapshot.attemptId) ||
      !Number.isSafeInteger(snapshot.amountMinor) ||
      snapshot.amountMinor < 1 || snapshot.amountMinor > 1_000_000_000 ||
      !["CZK", "EUR", "USD"].includes(snapshot.currency) ||
      !Number.isSafeInteger(snapshot.createdAt) ||
      !Number.isSafeInteger(snapshot.expiresAt) ||
      snapshot.createdAt < 0 || snapshot.expiresAt <= snapshot.createdAt
    ) {
      throw new PaymentError("barion_snapshot_invalid");
    }
  }
  async #request(
    path: string,
    init: RequestInit,
  ): Promise<Record<string, unknown>> {
    let response: Response;
    try {
      response = await this.#fetch(`https://api.test.barion.com${path}`, {
        ...init,
        redirect: "error",
        signal: AbortSignal.timeout(15_000),
      });
    } catch {
      throw new PaymentError("barion_remote_uncertain", true);
    }
    const reader = response.body?.getReader();
    const chunks: Uint8Array[] = [];
    let size = 0;
    if (reader) {
      for (;;) {
        const chunk = await reader.read();
        if (chunk.done) break;
        size += chunk.value.length;
        if (size > 262_144) {
          await reader.cancel();
          reject();
        }
        chunks.push(chunk.value);
      }
    }
    const bytes = new Uint8Array(size);
    let offset = 0;
    for (const chunk of chunks) {
      bytes.set(chunk, offset);
      offset += chunk.length;
    }
    let raw: unknown;
    try {
      raw = JSON.parse(new TextDecoder().decode(bytes));
    } catch {
      if (!response.ok) throw new BarionRequestError(response.status, null);
      reject();
    }
    const result = record(raw);
    if (
      !response.ok ||
      (Array.isArray(result.Errors) && result.Errors.length !== 0)
    ) {
      throw new BarionRequestError(
        response.status,
        record(Array.isArray(result.Errors) ? result.Errors[0] : null)
          .ErrorCode,
      );
    }
    if (
      Object.keys(result).length === 0 ||
      (result.Errors !== undefined && !Array.isArray(result.Errors))
    ) reject();
    return result;
  }
  /** Exactly one dispatch. Persistence must forbid another create after an
   * uncertain outcome; generic idempotency docs establish no retention window.
   */
  async createPayment(snapshot: CheckoutSnapshot): Promise<BarionCheckout> {
    this.#validate(snapshot);
    if (!snapshot.returnUrl) throw new PaymentError("barion_return_invalid");
    const target = new URL(snapshot.returnUrl);
    if (
      target.protocol !== "https:" || target.username || target.password ||
      target.hash ||
      !this.#configuration.allowedReturnOrigins.includes(target.origin)
    ) throw new PaymentError("barion_return_invalid");
    const now = Math.floor(Date.now() / 1000);
    const seconds = snapshot.expiresAt - now;
    if (seconds < 60 || seconds > 604_800) {
      throw new PaymentError("barion_reservation_expired");
    }
    const total = snapshot.amountMinor / 100;
    const result = await this.#request("/v2/Payment/Start", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": snapshot.attemptId,
      },
      body: JSON.stringify({
        POSKey: this.#configuration.posKey,
        PaymentType: "Immediate",
        PaymentRequestId: snapshot.attemptId,
        GuestCheckOut: true,
        FundingSources: ["All"],
        Currency: snapshot.currency,
        RedirectUrl: target.toString(),
        CallbackUrl: this.#configuration.callbackUrl,
        PaymentWindow: `${
          Math.floor(seconds / 3600).toString().padStart(2, "0")
        }:${Math.floor(seconds % 3600 / 60).toString().padStart(2, "0")}:${
          (seconds % 60).toString().padStart(2, "0")
        }`,
        Locale: {
          cs: "cs-CZ",
          en: "en-US",
          de: "de-DE",
          pl: "pl-PL",
          sk: "sk-SK",
          auto: "en-US",
        }[snapshot.locale ?? "en"],
        Transactions: [{
          POSTransactionId: snapshot.attemptId,
          Payee: this.#configuration.payee,
          Total: total,
          Items: [{
            Name: "Festapp integrační test",
            Description: snapshot.orderReference,
            Quantity: 1,
            Unit: "ks",
            UnitPrice: total,
            ItemTotal: total,
            SKU: snapshot.attemptId,
          }],
        }],
      }),
    });
    if (
      typeof result.PaymentId !== "string" || !uuid.test(result.PaymentId) ||
      (result.PaymentRequestId !== undefined &&
        result.PaymentRequestId !== snapshot.attemptId) ||
      typeof result.GatewayUrl !== "string" || typeof result.Status !== "string"
    ) reject();
    const url = this.validateCheckoutUrl(result.GatewayUrl as string);
    if (
      [...new URL(url).searchParams.values()][0].replaceAll("-", "")
        .toLowerCase() !==
        (result.PaymentId as string).replaceAll("-", "").toLowerCase()
    ) reject();
    return {
      id: result.PaymentId as string,
      url,
      status: result.Status as string,
    };
  }
  async paymentState(
    snapshot: CheckoutSnapshot,
    id: string,
  ): Promise<Record<string, unknown>> {
    this.#validate(snapshot);
    if (!uuid.test(id)) {
      throw new PaymentError("barion_payment_identity_invalid");
    }
    const result = await this.#request(
      `/v4/payment/${encodeURIComponent(id)}/paymentstate`,
      {
        headers: { "x-pos-key": this.#configuration.posKey },
      },
    );
    if (
      typeof result.PaymentId !== "string" ||
      result.PaymentId.toLowerCase() !== id.toLowerCase() ||
      result.PaymentRequestId !== snapshot.attemptId ||
      result.PaymentType !== "Immediate" ||
      result.Currency !== snapshot.currency ||
      typeof result.Status !== "string" ||
      !Array.isArray(result.Transactions) || result.Transactions.length > 100
    ) reject();
    return result;
  }

  /** Operator-only sandbox experiment. Caller persists a one-shot intent before
   * dispatch. No automatic refund retry or application refund capability.
   */
  async refund(
    snapshot: CheckoutSnapshot,
    id: string,
    transactionId: string,
    amountMinor: number,
    commandId: string,
  ) {
    this.#validate(snapshot);
    if (
      !uuid.test(id) || !uuid.test(transactionId) || !uuid.test(commandId) ||
      !Number.isSafeInteger(amountMinor) || amountMinor <= 0 ||
      amountMinor > snapshot.amountMinor
    ) {
      throw new PaymentError("barion_refund_invalid");
    }
    return await this.#request("/v2/Payment/Refund", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Idempotency-Key": commandId,
      },
      body: JSON.stringify({
        POSKey: this.#configuration.posKey,
        PaymentId: id,
        TransactionsToRefund: [{
          TransactionId: transactionId,
          POSTransactionId: commandId,
          AmountToRefund: amountMinor / 100,
        }],
      }),
    });
  }
}
