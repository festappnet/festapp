/** Compatibility entrypoints for issued Stripe URLs and existing edge routes.
 * All checkout/retry/HTTP lifecycle behavior is owned by payments/, not here.
 * This file retains only the Stripe webhook protocol and external name adapters.
 */
import {
  record,
  StripeBoundaryError,
  type VerifiedStripeEvent,
  verifyStripeEvent,
} from "./provider.ts";
import { observeStripeConnection } from "./connectionStatus.ts";
import {
  checkoutHandoff,
  checkoutPayment,
  recoverPaymentClaim,
  synchronizePaymentClaim,
} from "../payments/checkout.ts";
import {
  paymentHandler,
  paymentHeaders as headers,
  readPaymentBytes,
} from "../payments/http.ts";
import {
  stripeClaim,
  stripePaymentAdapter,
  type StripePaymentsDependencies,
} from "../payments/connectors/stripe.ts";
export type { StripePaymentsDependencies } from "../payments/connectors/stripe.ts";
const fail = (code: string): never => {
  throw new StripeBoundaryError(code, true);
};
export const readStripeBytes = readPaymentBytes;
export const checkoutStripePayment = (
  token: string,
  deps: StripePaymentsDependencies,
) => checkoutPayment(token, stripePaymentAdapter(deps));
export const checkoutStripeHandoff = (
  token: string,
  deps: StripePaymentsDependencies,
  consume = true,
) => checkoutHandoff(token, stripePaymentAdapter(deps), consume);
export const recoverStripeClaim = (
  value: unknown,
  deps: StripePaymentsDependencies,
) => recoverPaymentClaim(stripeClaim(value), stripePaymentAdapter(deps));
export const stripePaymentHandler = (
  request: Request,
  deps: StripePaymentsDependencies,
  readOnly = false,
) => paymentHandler(request, stripePaymentAdapter(deps), readOnly);
export async function stripeWebhookHandler(
  request: Request,
  deps: StripePaymentsDependencies,
) {
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, {
      status: 405,
      headers,
    });
  }
  let raw: Uint8Array<ArrayBuffer>, event: VerifiedStripeEvent | undefined;
  try {
    raw = await readStripeBytes(request, 1024 * 1024);
    for (const secret of deps.webhookSecrets) {
      try {
        event = await verifyStripeEvent(
          raw,
          request.headers.get("Stripe-Signature"),
          secret,
          deps.livemode,
        );
        break;
      } catch { /* bounded secret rotation */ }
    }
    if (!event) {
      return Response.json({ error: "invalid_signature" }, {
        status: 400,
        headers,
      });
    }
  } catch {
    return Response.json({ error: "invalid_request" }, {
      status: 400,
      headers,
    });
  }
  try {
    const object = event.data.object;
    const bodyHash = Array.from(
      new Uint8Array(await crypto.subtle.digest("SHA-256", raw)),
      (b) => b.toString(16).padStart(2, "0"),
    ).join("");
    if (
      [
        "account.updated",
        "account.application.deauthorized",
        "account.application.authorized",
      ].includes(event.type)
    ) {
      if (
        event.type === "account.updated" &&
        (object.object !== "account" || object.id !== event.account)
      ) fail("stripe_account_mismatch");
      const state = await observeStripeConnection(event.account, deps, {
        id: event.id,
        accountId: event.account,
        livemode: event.livemode,
        type: event.type,
        created: event.created,
        bodyHash,
      });
      return Response.json({
        received: true,
        ...(state === "unrelated" ? { unrelated: true } : {}),
      }, { headers });
    }
    const id = typeof object.id === "string" ? object.id : "";
    const attempt = record(object.metadata).festapp_attempt ??
      (object.object === "checkout.session"
        ? object.client_reference_id
        : null);
    const claim = record(
      await deps.rpc("claim_stripe_sync_internal", {
        p_account: event.account,
        p_livemode: event.livemode,
        p_attempt: typeof attempt === "string" &&
            /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/
              .test(attempt)
          ? attempt
          : null,
        p_session: object.object === "checkout.session" ? id : null,
        p_intent: object.object === "payment_intent"
          ? id
          : typeof object.payment_intent === "string"
          ? object.payment_intent
          : null,
      }),
    );
    if (claim.disposition === "unrelated") {
      return Response.json({ received: true, unrelated: true }, { headers });
    }
    if (claim.disposition !== "dispatch") fail("stripe_sync_busy");
    await synchronizePaymentClaim(stripeClaim(claim), {
      id: event.id,
      accountId: event.account,
      livemode: event.livemode,
      type: event.type,
      created: event.created,
      bodyHash,
    }, stripePaymentAdapter(deps));
    return Response.json({ received: true }, { headers });
  } catch {
    return Response.json({ error: "stripe_ingest_retry" }, {
      status: 503,
      headers,
    });
  }
}
