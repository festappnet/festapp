import {
  type CheckoutSnapshot,
  record,
  StripeBoundaryError,
  type StripeProvider,
  type VerifiedStripeEvent,
  verifyStripeEvent,
} from "./provider.ts";
import { openStripePaySource } from "./paySource.ts";
import { observeStripeConnection } from "./connectionStatus.ts";
import {
  disputeFact,
  paymentFact,
  refundFact,
  type StripeMovement,
} from "./facts.ts";
export type StripePaymentsDependencies = {
  livemode: boolean;
  allowedOrigins: string[];
  webhookSecrets: string[];
  verifyPlatform(): Promise<void>;
  provider: Pick<
    StripeProvider,
    | "createOrRecoverSession"
    | "session"
    | "sessionCandidates"
    | "refunds"
    | "disputes"
    | "account"
  >;
  rpc(name: string, args: Record<string, unknown>): Promise<unknown>;
  openSource?: typeof openStripePaySource;
};
const fail = (code: string): never => {
  throw new StripeBoundaryError(code, true);
};
async function preparedClaim(
  value: unknown,
  deps: StripePaymentsDependencies,
  creation = false,
) {
  await deps.verifyPlatform();
  const claim = record(value), raw = record(claim.snapshot);
  if (
    typeof raw.returnBaseUrl !== "string" || raw.livemode !== deps.livemode ||
    typeof raw.attemptId !== "string" || typeof claim.lease !== "string"
  ) fail("stripe_dispatch_invalid");
  let target: URL;
  if (creation) {
    const source = await (deps.openSource ?? openStripePaySource)(claim.source);
    target = new URL(raw.returnBaseUrl as string);
    if (
      !deps.allowedOrigins.includes(target.origin) || target.search ||
      target.hash || target.username || target.password ||
      !target.pathname.endsWith("/stripe/return")
    ) fail("stripe_return_origin_invalid");
    target.searchParams.set("return_handle", source.returnHandle);
  }
  const snapshot: CheckoutSnapshot = {
    attemptId: raw.attemptId as string,
    accountId: raw.accountId as string,
    livemode: raw.livemode as boolean,
    amountMinor: raw.amountMinor as number,
    currency: raw.currency as string,
    orderReference: raw.orderReference as string,
    expiresAt: raw.expiresAt as number,
    createdAt: raw.createdAt as number,
    idempotencyKey: raw.idempotencyKey as string,
    ...(creation ? { returnUrl: target!.toString() } : {}),
  };
  return { claim, raw, snapshot, lease: claim.lease as string };
}
function rawSessionPresent(value: unknown) {
  return typeof record(record(value).snapshot).sessionId === "string";
}
function committed(value: unknown) {
  const receipt = record(record(value).data);
  if (
    receipt.committed !== true || record(receipt.payment).method !== "stripe"
  ) fail("stripe_ingest_not_committed");
  return record(receipt.payment);
}
async function recoveryEvent(snapshot: CheckoutSnapshot) {
  return {
    id: "evt_reconcile" + crypto.randomUUID().replaceAll("-", ""),
    bodyHash: "0".repeat(64),
    accountId: snapshot.accountId,
    livemode: snapshot.livemode,
    type: "festapp.reconcile",
    created: Math.floor(Date.now() / 1000),
  };
}
export async function synchronizeStripeClaim(
  value: unknown,
  event: Record<string, unknown> | null,
  deps: StripePaymentsDependencies,
  current?: Record<string, unknown>,
) {
  const { raw, snapshot, lease } = await preparedClaim(value, deps);
  const session = current ??
    await deps.provider.session(snapshot, raw.sessionId as string);
  const payment = paymentFact(snapshot, session);
  const movements: StripeMovement[] = payment ? [payment] : [];
  let refundCursor: string | null = null;
  let disputes: unknown[] = [];
  const intent = typeof session.payment_intent === "string"
    ? session.payment_intent
    : record(session.payment_intent).id;
  if (payment) {
    const refunds = await deps.provider.refunds(
      snapshot,
      intent as string,
      typeof raw.refundCursor === "string" ? raw.refundCursor : undefined,
    );
    for (const refund of refunds.data) {
      const fact = refundFact(snapshot, intent as string, refund);
      if (fact) movements.push(fact);
    }
    refundCursor = refunds.nextCursor;
    if (!refundCursor) {
      disputes = (await deps.provider.disputes(snapshot, intent as string)).map(
        (d) => disputeFact(snapshot, intent as string, d),
      );
    }
  }
  return committed(
    await deps.rpc("ingest_stripe_payment_internal", {
      p_attempt: snapshot.attemptId,
      p_lease: lease,
      p_event: event ?? await recoveryEvent(snapshot),
      p_facts: {
        observedAt: new Date().toISOString(),
        sessionId: session.id,
        paymentIntentId: intent ?? null,
        sessionStatus: session.status,
        movements,
        disputes,
        refundCursor,
      },
    }),
  );
}
export async function checkoutStripePayment(
  token: string,
  deps: StripePaymentsDependencies,
): Promise<{ payment: Record<string, unknown>; checkoutUrl?: string }> {
  const claim = record(
    await deps.rpc("claim_stripe_checkout_internal", {
      p_token: token,
      p_livemode: deps.livemode,
    }),
  );
  if (claim.disposition === "read" || claim.disposition === "busy") {
    return { payment: record(claim.payment) };
  }
  if (claim.disposition !== "dispatch") fail("stripe_dispatch_invalid");
  const { snapshot, raw, lease } = await preparedClaim(
    claim,
    deps,
    !rawSessionPresent(claim),
  );
  try {
    const session = raw.sessionId
      ? await deps.provider.session(snapshot, raw.sessionId as string)
      : await deps.provider.createOrRecoverSession(snapshot);
    if (session.status !== "open") {
      return {
        payment: await synchronizeStripeClaim(
          claim,
          null,
          deps,
          await deps.provider.session(snapshot, session.id as string),
        ),
      };
    }
    const url = new URL(String(session.url));
    if (
      url.protocol !== "https:" || url.hostname !== "checkout.stripe.com" ||
      url.username || url.password || url.port
    ) fail("provider_response_invalid");
    const receipt = record(
      await deps.rpc("commit_stripe_checkout_session_internal", {
        p_attempt: snapshot.attemptId,
        p_lease: lease,
        p_session: session.id,
        p_url: url.toString(),
        p_expires: session.expires_at,
      }),
    );
    if (receipt.committed !== true) fail("stripe_checkout_not_committed");
    const payment = record(receipt.payment);
    return {
      payment,
      ...(payment.status === "open" ? { checkoutUrl: url.toString() } : {}),
    };
  } catch (error) {
    await deps.rpc("fail_stripe_checkout_internal", {
      p_attempt: snapshot.attemptId,
      p_lease: lease,
    }).catch(() => {});
    throw error;
  }
}

/** A machine retry never chooses a new attempt, expiry or idempotency key. */
export async function recoverStripeClaim(
  value: unknown,
  deps: StripePaymentsDependencies,
) {
  const rawClaim = record(record(value).snapshot);
  const creation = !rawClaim.sessionId &&
    Math.floor(Date.now() / 1000) < Number(rawClaim.expiresAt);
  const { raw, snapshot } = await preparedClaim(value, deps, creation);
  if (!raw.sessionId && Math.floor(Date.now() / 1000) >= snapshot.expiresAt) {
    const page = await deps.provider.sessionCandidates(
      snapshot,
      typeof raw.sessionLookupCursor === "string"
        ? raw.sessionLookupCursor
        : undefined,
    );
    const matches = new Set<string>(page.matches);
    if (typeof raw.sessionLookupFound === "string") {
      matches.add(raw.sessionLookupFound);
    }
    if (matches.size > 1) fail("stripe_multiple_sessions_require_resolution");
    const found = [...matches][0] ?? null;
    if (page.nextCursor) {
      await deps.rpc("checkpoint_stripe_session_lookup_internal", {
        p_attempt: snapshot.attemptId,
        p_lease: record(value).lease,
        p_cursor: page.nextCursor,
        p_found: found,
      });
      return {
        method: "stripe",
        status: "pending",
        reconciliationPending: true,
      };
    }
    if (found) {
      return await synchronizeStripeClaim(
        value,
        null,
        deps,
        await deps.provider.session(snapshot, found),
      );
    }
    return committed(
      await deps.rpc("ingest_stripe_payment_internal", {
        p_attempt: snapshot.attemptId,
        p_lease: record(value).lease,
        p_event: await recoveryEvent(snapshot),
        p_facts: {
          observedAt: new Date().toISOString(),
          sessionId: null,
          paymentIntentId: null,
          sessionStatus: "expired",
          movements: [],
          disputes: [],
          noSessionVerified: true,
        },
      }),
    );
  }
  const session = raw.sessionId
    ? await deps.provider.session(snapshot, raw.sessionId as string)
    : await deps.provider.createOrRecoverSession(snapshot);
  return await synchronizeStripeClaim(
    value,
    null,
    deps,
    await deps.provider.session(snapshot, session.id as string),
  );
}
export async function readStripeBytes(request: Request, limit: number) {
  const reader = request.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let length = 0;
  for (;;) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > limit) {
      await reader.cancel();
      throw new StripeBoundaryError("stripe_request_too_large");
    }
    chunks.push(value);
  }
  const result = new Uint8Array(length);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.length;
  }
  return result;
}
const headers = {
  "Cache-Control": "no-store",
  "Referrer-Policy": "no-referrer",
};
export async function checkoutStripeHandoff(
  token: string,
  deps: StripePaymentsDependencies,
  consume = true,
) {
  const result = record(
    await deps.rpc("read_stripe_handoff_internal", {
      p_token: token,
      p_livemode: deps.livemode,
      p_consume: consume,
    }),
  );
  if (!consume) return { payment: record(result.payment) };
  const secrets = await (deps.openSource ?? openStripePaySource)(result.source);
  return await checkoutStripePayment(secrets.payToken, deps);
}
export async function stripePaymentHandler(
  request: Request,
  deps: StripePaymentsDependencies,
  readOnly = false,
) {
  const origin = request.headers.get("Origin");
  if (origin && !deps.allowedOrigins.includes(origin)) {
    return Response.json({ error: "origin_denied" }, { status: 403, headers });
  }
  const cors = {
    ...headers,
    ...(origin
      ? { "Access-Control-Allow-Origin": origin, "Vary": "Origin" }
      : {}),
    "Access-Control-Allow-Headers":
      "content-type,authorization,apikey,x-client-info",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== "POST") {
    return Response.json({ error: "method_not_allowed" }, {
      status: 405,
      headers: cors,
    });
  }
  try {
    const body = record(
      JSON.parse(
        new TextDecoder().decode(await readStripeBytes(request, 4096)),
      ),
    );
    if (
      typeof body.token !== "string" || !/^[a-f0-9]{64}$/.test(body.token) ||
      Object.keys(body).some((key) =>
        key !== "token" && (readOnly || key !== "action")
      ) ||
      (body.action !== undefined && body.action !== "status" &&
        body.action !== "prepare" && body.action !== "handoff" &&
        body.action !== "status_handoff")
    ) {
      return Response.json({ error: "invalid_request" }, {
        status: 400,
        headers: cors,
      });
    }
    const result = readOnly
      ? {
        payment: await deps.rpc("read_stripe_return_internal", {
          p_token: body.token,
          p_livemode: deps.livemode,
        }),
      }
      : body.action === "status"
      ? {
        payment: await deps.rpc("read_stripe_pay_status_internal", {
          p_token: body.token,
          p_livemode: deps.livemode,
        }),
      }
      : body.action === "handoff" || body.action === "status_handoff"
      ? await checkoutStripeHandoff(body.token, deps, body.action === "handoff")
      : await checkoutStripePayment(body.token, deps);
    return Response.json(result, { headers: cors });
  } catch (error) {
    if (
      error instanceof StripeBoundaryError &&
      error.code === "invalid_capability"
    ) {
      return Response.json({ error: "invalid_capability" }, {
        status: 403,
        headers: cors,
      });
    }
    if (
      error instanceof StripeBoundaryError &&
      error.code === "payment_rate_limited"
    ) {
      return Response.json({ error: "payment_rate_limited" }, {
        status: 429,
        headers: { ...cors, "Retry-After": "60" },
      });
    }
    return Response.json({ error: "stripe_payment_temporarily_unavailable" }, {
      status: 503,
      headers: cors,
    });
  }
}
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
    await synchronizeStripeClaim(claim, {
      id: event.id,
      accountId: event.account,
      livemode: event.livemode,
      type: event.type,
      created: event.created,
      bodyHash,
    }, deps);
    return Response.json({ received: true }, { headers });
  } catch {
    return Response.json({ error: "stripe_ingest_retry" }, {
      status: 503,
      headers,
    });
  }
}
