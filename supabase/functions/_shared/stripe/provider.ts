/** Provider boundary only. SQL owns amounts, recipients, capabilities and states.
 * No environment reads, hidden retries, OAuth account creation or money mutations.
 */
export class StripeBoundaryError extends Error {
  constructor(
    public readonly code: string,
    public readonly retryable = false,
  ) {
    super(code);
    this.name = "StripeBoundaryError";
  }
}
function fail(code: string): never {
  throw new StripeBoundaryError(code);
}
const encoder = new TextEncoder();
const accountPattern = /^acct_[A-Za-z0-9]+$/;
// MVP currencies are deliberately bounded; availability still requires server preflight.
const exponents: Record<string, number> = {
  CZK: 2,
  EUR: 2,
  PLN: 2,
  USD: 2,
  GBP: 2,
  JPY: 0,
  KWD: 3,
};
export function toMinorUnits(decimal: string, currency: string): number {
  const exponent = exponents[currency.toUpperCase()];
  if (exponent === undefined) return fail("payment_currency_not_supported");
  const match = /^(0|[1-9][0-9]*)(?:\.([0-9]+))?$/.exec(decimal);
  if (!match || (match[2]?.length ?? 0) > exponent) {
    return fail("payment_amount_invalid");
  }
  const value = BigInt(match[1]) * 10n ** BigInt(exponent) +
    BigInt((match[2] ?? "").padEnd(exponent, "0") || "0");
  if (value > BigInt(Number.MAX_SAFE_INTEGER)) {
    return fail("payment_amount_invalid");
  }
  return Number(value);
}
export type AccountReadiness = {
  accountId: string;
  businessName: string | null;
  country: string | null;
  modelVerified: boolean;
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  cardPaymentsActive: boolean;
  ready: boolean;
};
export function accountReadiness(
  value: unknown,
  expectedAccount: string,
): AccountReadiness {
  const a = record(value);
  if (
    !accountPattern.test(expectedAccount) || a.id !== expectedAccount ||
    a.object !== "account"
  ) {
    return fail("stripe_account_mismatch");
  }
  const c = record(a.controller);
  // Explicitly verify v1's financial responsibilities. Do not infer them from account type.
  const modelVerified = record(c.fees).payer === "account" &&
    record(c.losses).payments === "stripe" &&
    record(c.stripe_dashboard).type === "full";
  const chargesEnabled = a.charges_enabled === true;
  const cardPaymentsActive = record(a.capabilities).card_payments === "active";
  return {
    accountId: expectedAccount,
    businessName: typeof record(a.business_profile).name === "string"
      ? record(a.business_profile).name as string
      : null,
    country: typeof a.country === "string" ? a.country : null,
    modelVerified,
    chargesEnabled,
    cardPaymentsActive,
    payoutsEnabled: a.payouts_enabled === true,
    ready: modelVerified && chargesEnabled && cardPaymentsActive,
  };
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
}>;
export type ProviderOptions = {
  secretKey: string;
  livemode: boolean;
  apiVersion: string;
  allowedReturnOrigins: readonly string[];
  fetch?: typeof fetch;
  now?: () => number;
};
export class StripeProvider {
  private readonly fetcher: typeof fetch;
  private readonly now: () => number;
  constructor(private readonly options: ProviderOptions) {
    if (
      !new RegExp(
        `^(sk|rk)_${options.livemode ? "live" : "test"}_[A-Za-z0-9]+$`,
      ).test(options.secretKey) ||
      !/^\d{4}-\d{2}-\d{2}\.[a-z]+$/.test(options.apiVersion)
    ) fail("stripe_configuration_invalid");
    for (const origin of options.allowedReturnOrigins) {
      const u = new URL(origin);
      const testLoopback = !options.livemode && u.protocol === "http:" &&
        ["127.0.0.1", "localhost", "[::1]"].includes(u.hostname);
      if (u.origin !== origin || (u.protocol !== "https:" && !testLoopback)) {
        fail("stripe_return_origin_invalid");
      }
    }
    this.fetcher = options.fetch ?? fetch;
    this.now = options.now ?? (() => Math.floor(Date.now() / 1000));
  }
  private async request(
    path: string,
    account: string,
    body?: URLSearchParams,
    key?: string,
    platform = false,
  ): Promise<Record<string, unknown>> {
    if (
      !accountPattern.test(account) ||
      !/^\/[a-z0-9_/]+(?:\?[a-z0-9_.\[\]=&]+)?$/i.test(path)
    ) fail("stripe_request_invalid");
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.options.secretKey}`,
      "Stripe-Account": account,
      "Stripe-Version": this.options.apiVersion,
    };
    if (platform) {
      if (path !== "/account" || body) fail("stripe_request_invalid");
      delete headers["Stripe-Account"];
    }
    if (key) headers["Idempotency-Key"] = key;
    if (body) headers["Content-Type"] = "application/x-www-form-urlencoded";
    let response: Response;
    try {
      response = await this.fetcher(`https://api.stripe.com/v1${path}`, {
        method: body ? "POST" : "GET",
        headers,
        body,
        signal: AbortSignal.timeout(15_000),
        redirect: "error",
      });
    } catch {
      throw new StripeBoundaryError("provider_temporarily_unavailable", true);
    }
    if (!response.ok) {
      if (
        path === "/account" && !platform &&
        (response.status === 400 || response.status === 403)
      ) {
        try {
          if (
            record(record(await response.json()).error).code ===
              "account_invalid"
          ) fail("stripe_account_access_unavailable");
        } catch (error) {
          if (error instanceof StripeBoundaryError) throw error;
        }
      }
      // Never expose raw provider errors, response bodies or keys in receipts/logs.
      throw new StripeBoundaryError(
        response.status === 429 || response.status >= 500
          ? "provider_temporarily_unavailable"
          : "stripe_request_rejected",
        response.status === 429 || response.status >= 500,
      );
    }
    try {
      return record(await response.json());
    } catch {
      throw new StripeBoundaryError("provider_response_invalid", true);
    }
  }
  async account(account: string): Promise<AccountReadiness> {
    return accountReadiness(await this.request("/account", account), account);
  }
  async verifyPlatform(expectedAccount: string): Promise<void> {
    const value = await this.request(
      "/account",
      expectedAccount,
      undefined,
      undefined,
      true,
    );
    if (value.object !== "account" || value.id !== expectedAccount) {
      fail("stripe_platform_mismatch");
    }
  }
  private validateSnapshot(s: CheckoutSnapshot, requireReturn = false) {
    if (
      s.livemode !== this.options.livemode ||
      !accountPattern.test(s.accountId) ||
      !Number.isSafeInteger(s.amountMinor) || s.amountMinor <= 0 ||
      !/^[A-Z]{3}$/.test(s.currency) || exponents[s.currency] === undefined ||
      !/^[a-zA-Z0-9_-]{8,128}$/.test(s.attemptId) ||
      !/^[a-zA-Z0-9:_-]{8,255}$/.test(s.idempotencyKey) ||
      !s.orderReference || s.orderReference.length > 128 ||
      !Number.isSafeInteger(s.expiresAt) ||
      !Number.isSafeInteger(s.createdAt) ||
      s.createdAt > this.now()
    ) fail("stripe_snapshot_invalid");
    if (!requireReturn) return;
    if (typeof s.returnUrl !== "string") fail("stripe_return_origin_invalid");
    const u = new URL(s.returnUrl!);
    if (
      !this.options.allowedReturnOrigins.includes(u.origin) || u.username ||
      u.password || u.hash ||
      [...u.searchParams.keys()].some((key) => key !== "return_handle") ||
      !/^[a-f0-9]{64}$/.test(u.searchParams.get("return_handle") ?? "")
    ) fail("stripe_return_origin_invalid");
  }
  async createOrRecoverSession(
    s: CheckoutSnapshot,
  ): Promise<Record<string, unknown>> {
    this.validateSnapshot(s, true);
    const now = this.now();
    // Never renew an uncertain attempt beyond Stripe's 24h idempotency retention.
    if (now - s.createdAt >= 23 * 3600) {
      fail("checkout_requires_reconciliation");
    }
    // Validate the original durable window. Replaying an already-created Session
    // must retain the same expires_at even after its remaining time drops below
    // Stripe's minimum for a NEW Session. Stripe's idempotency cache owns replay.
    if (s.expiresAt - s.createdAt < 1800 || s.expiresAt - s.createdAt > 86400) {
      fail("reservation_checkout_window_invalid");
    }
    if (s.expiresAt <= now) fail("reservation_expired");
    const body = new URLSearchParams({
      mode: "payment",
      "payment_method_types[0]": "card",
      "line_items[0][price_data][currency]": s.currency.toLowerCase(),
      "line_items[0][price_data][unit_amount]": String(s.amountMinor),
      "line_items[0][price_data][product_data][name]": s.orderReference,
      "line_items[0][quantity]": "1",
      client_reference_id: s.attemptId,
      "payment_intent_data[metadata][festapp_attempt]": s.attemptId,
      "metadata[festapp_attempt]": s.attemptId,
      "adaptive_pricing[enabled]": "false",
      "automatic_tax[enabled]": "false",
      allow_promotion_codes: "false",
      expires_at: String(s.expiresAt),
      success_url: s.returnUrl!,
      cancel_url: s.returnUrl!,
    });
    const session = await this.request(
      "/checkout/sessions",
      s.accountId,
      body,
      s.idempotencyKey,
    );
    this.validateSession(session, s);
    return session;
  }
  async createCheckout(
    s: CheckoutSnapshot,
  ): Promise<{ sessionId: string; url: string; expiresAt: number }> {
    const session = await this.createOrRecoverSession(s);
    if (session.status !== "open" || typeof session.url !== "string") {
      fail("checkout_requires_reconciliation");
    }
    const url = new URL(session.url);
    if (
      url.protocol !== "https:" || url.hostname !== "checkout.stripe.com" ||
      url.username || url.password || url.port
    ) {
      fail("provider_response_invalid");
    }
    return {
      sessionId: session.id as string,
      url: session.url as string,
      expiresAt: session.expires_at as number,
    };
  }
  async session(s: CheckoutSnapshot, sessionId: string) {
    this.validateSnapshot(s);
    if (!/^cs_(?:test_|live_)?[A-Za-z0-9]+$/.test(sessionId)) {
      fail("stripe_request_invalid");
    }
    const session = await this.request(
      `/checkout/sessions/${sessionId}?expand[]=payment_intent.latest_charge`,
      s.accountId,
    );
    this.validateSession(session, s);
    return session;
  }
  /** Read-only recovery after the original Session creation response was lost.
   * The fixed window and cursor never permit a fresh financial attempt. */
  async sessionCandidates(s: CheckoutSnapshot, cursor?: string) {
    this.validateSnapshot(s);
    if (
      cursor !== undefined && !/^cs_(?:test_|live_)?[A-Za-z0-9]+$/.test(cursor)
    ) fail("stripe_request_invalid");
    const page = await this.request(
      `/checkout/sessions?created[gte]=${
        Math.max(0, s.createdAt - 300)
      }&created[lte]=${s.expiresAt}&limit=100${
        cursor ? `&starting_after=${cursor}` : ""
      }`,
      s.accountId,
    );
    if (
      !Array.isArray(page.data) || page.data.length > 100 ||
      typeof page.has_more !== "boolean"
    ) fail("provider_response_invalid");
    const matches: string[] = [];
    for (const raw of page.data as unknown[]) {
      const item = record(raw);
      if (
        item.object !== "checkout.session" || typeof item.id !== "string" ||
        !/^cs_(?:test_|live_)?[A-Za-z0-9]+$/.test(item.id) ||
        item.livemode !== s.livemode
      ) fail("provider_response_invalid");
      if (
        item.client_reference_id === s.attemptId ||
        record(item.metadata).festapp_attempt === s.attemptId
      ) {
        this.validateSession(item, s);
        matches.push(item.id as string);
      }
    }
    const nextCursor = page.has_more
      ? record((page.data as unknown[]).at(-1)).id
      : null;
    if (page.has_more && !nextCursor) fail("provider_response_invalid");
    return { matches, nextCursor: nextCursor as string | null };
  }
  async refunds(s: CheckoutSnapshot, intentId: string, cursor?: string) {
    this.validateSnapshot(s);
    if (
      !/^pi_[A-Za-z0-9]+$/.test(intentId) ||
      (cursor !== undefined && !/^re_[A-Za-z0-9]+$/.test(cursor))
    ) {
      fail("stripe_request_invalid");
    }
    const page = await this.request(
      `/refunds?payment_intent=${intentId}&limit=100${
        cursor ? `&starting_after=${cursor}` : ""
      }`,
      s.accountId,
    );
    if (
      !Array.isArray(page.data) || page.data.length > 100 ||
      typeof page.has_more !== "boolean" ||
      page.data.some((item) =>
        !/^re_[A-Za-z0-9]+$/.test(String(record(item).id))
      )
    ) {
      fail("provider_response_invalid");
    }
    const nextCursor = page.has_more ? record(page.data.at(-1)).id : null;
    if (page.has_more && !nextCursor) fail("provider_response_invalid");
    return {
      data: page.data as Record<string, unknown>[],
      nextCursor: nextCursor as string | null,
    };
  }
  async disputes(s: CheckoutSnapshot, intentId: string) {
    this.validateSnapshot(s);
    if (!/^pi_[A-Za-z0-9]+$/.test(intentId)) fail("stripe_request_invalid");
    const page = await this.request(
      `/disputes?payment_intent=${intentId}&limit=100`,
      s.accountId,
    );
    if (
      !Array.isArray(page.data) || page.data.length > 100 ||
      page.has_more !== false ||
      page.data.some((item) =>
        !/^(?:dp|du)_[A-Za-z0-9]+$/.test(String(record(item).id))
      )
    ) {
      fail("provider_response_invalid");
    }
    return page.data as Record<string, unknown>[];
  }
  private validateSession(
    session: Record<string, unknown>,
    s: CheckoutSnapshot,
  ) {
    if (
      session.object !== "checkout.session" || typeof session.id !== "string" ||
      !/^cs_(?:test_|live_)?[A-Za-z0-9]+$/.test(session.id) ||
      session.livemode !== s.livemode ||
      session.amount_total !== s.amountMinor ||
      session.currency !== s.currency.toLowerCase() ||
      session.client_reference_id !== s.attemptId ||
      session.expires_at !== s.expiresAt || session.mode !== "payment" ||
      !Array.isArray(session.payment_method_types) ||
      session.payment_method_types.length !== 1 ||
      session.payment_method_types[0] !== "card"
    ) fail("stripe_session_mismatch");
  }
}
export type VerifiedStripeEvent = {
  id: string;
  account: string;
  livemode: boolean;
  type: string;
  created: number;
  data: { object: Record<string, unknown> };
};
/** Authenticate the ORIGINAL bytes before JSON parsing. Signature rotation accepts any valid v1. */
export async function verifyStripeEvent(
  raw: Uint8Array,
  signature: string | null,
  secret: string,
  livemode: boolean,
  now = Math.floor(Date.now() / 1000),
): Promise<VerifiedStripeEvent> {
  if (!secret.startsWith("whsec_") || secret.length < 12) {
    fail("stripe_configuration_invalid");
  }
  if (!signature || raw.byteLength > 1024 * 1024) {
    fail("stripe_signature_invalid");
  }
  const parts = signature.split(",").map((p) => p.split("="));
  const timestamps = parts.filter(([k]) => k === "t");
  const candidates = parts.filter(([k, v]) =>
    k === "v1" && /^[a-f0-9]{64}$/.test(v ?? "")
  );
  if (
    timestamps.length !== 1 || !/^\d{1,12}$/.test(timestamps[0][1] ?? "") ||
    candidates.length === 0
  ) {
    fail("stripe_signature_invalid");
  }
  const timestamp = timestamps[0][1];
  if (Math.abs(now - Number(timestamp)) > 300) fail("stripe_signature_invalid");
  const prefix = encoder.encode(`${timestamp}.`);
  const signed = new Uint8Array(prefix.length + raw.length);
  signed.set(prefix);
  signed.set(raw, prefix.length);
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"],
  );
  let verified = false;
  for (const [, hex] of candidates) {
    const bytes = Uint8Array.from(hex.match(/../g)!, (v) => parseInt(v, 16));
    verified = (await crypto.subtle.verify("HMAC", key, bytes, signed)) ||
      verified;
  }
  if (!verified) fail("stripe_signature_invalid");
  let event: Record<string, unknown>;
  try {
    event = record(
      JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(raw)),
    );
  } catch {
    return fail("stripe_event_invalid");
  }
  if (
    event.livemode !== livemode || typeof event.id !== "string" ||
    !/^evt_[A-Za-z0-9]+$/.test(event.id) ||
    typeof event.account !== "string" || !accountPattern.test(event.account) ||
    typeof event.type !== "string" ||
    (!Number.isSafeInteger(event.created) || (event.created as number) < 0) ||
    typeof record(event.data).object !== "object" ||
    record(event.data).object === null ||
    Array.isArray(record(event.data).object)
  ) fail("stripe_event_invalid");
  return event as VerifiedStripeEvent;
}
