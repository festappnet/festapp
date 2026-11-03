import { prepareStripeOrderDelivery } from "./orderDelivery.ts";
import { strict as assert } from "node:assert";
import { StripeProvider } from "./provider.ts";
import { reconcileStripePayments } from "./reconcile.ts";
import {
  checkoutStripeHandoff,
  checkoutStripePayment,
  stripePaymentHandler,
  type StripePaymentsDependencies,
  stripeWebhookHandler,
} from "./payments.ts";
const now = Math.floor(Date.now() / 1000);
const attempt = "12345678-1234-4234-8234-123456789abc";
const snapshot = {
  attemptId: attempt,
  accountId: "acct_fixture",
  livemode: false,
  amountMinor: 12345,
  currency: "CZK",
  orderReference: "Order ABCD",
  createdAt: now,
  expiresAt: now + 1860,
  idempotencyKey: "festapp:checkout:" + attempt,
  returnBaseUrl: "https://tickets.example/stripe/return",
  sessionId: null,
};
const session = {
  object: "checkout.session",
  id: "cs_test_fixture",
  livemode: false,
  mode: "payment",
  amount_total: 12345,
  currency: "czk",
  client_reference_id: attempt,
  expires_at: now + 1860,
  payment_method_types: ["card"],
  status: "open",
  payment_status: "unpaid",
  url: "https://checkout.stripe.com/c/pay/cs_test_fixture",
};
function fixture(
  options: {
    paid?: boolean;
    rejectReceipt?: boolean;
    timeout?: boolean;
    refundPages?: boolean;
    expiredUnknown?: boolean;
    missingSession?: boolean;
    accountRevoked?: boolean;
  } = {},
) {
  const calls: { name: string; args: Record<string, unknown> }[] = [];
  const requests: { url: string; key: string | null }[] = [];
  let timeout = options.timeout;
  let refundCursor: string | null = null;
  let lookupCursor: string | null = null, lookupFound: string | null = null;
  const savedSnapshot = options.expiredUnknown
    ? { ...snapshot, createdAt: now - 5000, expiresAt: now - 3140 }
    : snapshot;
  const savedSession = { ...session, expires_at: savedSnapshot.expiresAt };
  const provider = new StripeProvider({
    secretKey: "sk_test_fixture",
    livemode: false,
    apiVersion: "2025-06-30.basil",
    allowedReturnOrigins: ["https://tickets.example"],
    now: () => now,
    fetch: async (input, init) => {
      const url = String(input);
      requests.push({
        url,
        key: new Headers(init?.headers).get("Idempotency-Key"),
      });
      assert.equal(
        new Headers(init?.headers).get("Stripe-Account"),
        "acct_fixture",
      );
      if (timeout) {
        timeout = false;
        throw new Error("private provider error");
      }
      if (url.endsWith("/account")) {
        return options.accountRevoked
          ? Response.json({
            error: {
              code: "account_invalid",
              message: "private provider details",
            },
          }, { status: 403 })
          : Response.json({
            id: "acct_fixture",
            object: "account",
            charges_enabled: true,
            payouts_enabled: false,
            capabilities: { card_payments: "active" },
            controller: {
              fees: { payer: "account" },
              losses: { payments: "stripe" },
              stripe_dashboard: { type: "full" },
            },
          });
      }
      if (url.includes("/checkout/sessions?")) {
        if (options.missingSession) {
          return Response.json({ data: [], has_more: false });
        }
        const more = !url.includes("starting_after=");
        return Response.json({
          data: more ? [savedSession] : [],
          has_more: more,
        });
      }
      if (url.includes("/refunds?")) {
        if (options.refundPages) {
          const more = !url.includes("starting_after=re_pageOne");
          return Response.json({
            data: [{
              id: more ? "re_pageOne" : "re_pageTwo",
              object: "refund",
              payment_intent: "pi_fixture",
              currency: "czk",
              amount: 100,
              status: "succeeded",
              created: now,
            }],
            has_more: more,
          });
        }
        return Response.json({ data: [], has_more: false });
      }
      if (url.includes("/disputes?")) {
        return Response.json({ data: [], has_more: false });
      }
      return Response.json(
        options.paid
          ? {
            ...savedSession,
            status: "complete",
            payment_status: "paid",
            url: null,
            payment_intent: {
              object: "payment_intent",
              id: "pi_fixture",
              status: "succeeded",
              livemode: false,
              amount: 12345,
              amount_received: 12345,
              currency: "czk",
              metadata: { festapp_attempt: attempt },
              latest_charge: {
                id: "ch_fixture",
                created: options.expiredUnknown ? now - 4500 : now,
              },
            },
          }
          : savedSession,
      );
    },
  });
  const claim = {
    disposition: "dispatch",
    lease: "87654321-1234-4234-8234-123456789abc",
    snapshot: savedSnapshot,
    source: {},
  };
  const deps: StripePaymentsDependencies = {
    livemode: false,
    allowedOrigins: ["https://tickets.example"],
    webhookSecrets: ["whsec_fixture"],
    provider,
    verifyPlatform: () => Promise.resolve(),
    openSource: () =>
      Promise.resolve({
        payToken: "a".repeat(64),
        returnHandle: "b".repeat(64),
      }),
    rpc: async (name, args) => {
      calls.push({ name, args });
      if (name === "claim_stripe_checkout_internal") return claim;
      if (name === "claim_stripe_connection_status_internal") {
        return {
          disposition: "dispatch",
          connectionId: attempt,
          lease: claim.lease,
        };
      }
      if (name === "commit_stripe_connection_status_internal") {
        return { committed: !options.rejectReceipt, connectionId: attempt };
      }
      if (name === "get_recoverable_stripe_attempts_internal") {
        return [{ attemptId: attempt, accountId: "acct_fixture" }];
      }
      if (name === "get_recoverable_stripe_connections_internal") return [];
      if (name === "claim_stripe_sync_internal") {
        return {
          ...claim,
          snapshot: {
            ...savedSnapshot,
            sessionId: options.expiredUnknown
              ? null
              : args.p_session ?? session.id,
            refundCursor,
            sessionLookupCursor: lookupCursor,
            sessionLookupFound: lookupFound,
          },
        };
      }
      if (name === "checkpoint_stripe_session_lookup_internal") {
        lookupCursor = args.p_cursor as string;
        lookupFound = args.p_found as string | null;
        return null;
      }
      if (name === "commit_stripe_checkout_session_internal") {
        return {
          committed: !options.rejectReceipt,
          payment: { method: "stripe", status: "open" },
        };
      }
      if (name === "ingest_stripe_payment_internal") {
        refundCursor = (args.p_facts as Record<string, unknown>).refundCursor as
          | string
          | null;
        return {
          data: {
            committed: !options.rejectReceipt,
            payment: {
              method: "stripe",
              status:
                (args.p_facts as Record<string, unknown>).noSessionVerified
                  ? "expired"
                  : refundCursor
                  ? "pending"
                  : "paid",
              reconciliationPending: !!refundCursor,
            },
          },
        };
      }
      if (name === "read_stripe_return_internal") {
        return {
          method: "stripe",
          status: "paid",
          allowedActions: ["refresh"],
        };
      }
      return null;
    },
  };
  return { deps, calls, requests };
}
Deno.test("A25 durable refund cursor resumes one bounded page without another Checkout", async () => {
  const { deps, calls, requests } = fixture({ paid: true, refundPages: true });
  assert.equal((await reconcileStripePayments(deps))[0].state, "continuing");
  assert.equal((await reconcileStripePayments(deps))[0].state, "completed");
  const reads = requests.filter((r) => r.url.includes("/refunds?"));
  assert.equal(reads.length, 2);
  assert(!reads[0].url.includes("starting_after"));
  assert(reads[1].url.includes("starting_after=re_pageOne"));
  assert.equal(
    requests.filter((r) => r.url.endsWith("/checkout/sessions")).length,
    0,
  );
  assert.equal(
    calls.filter((c) => c.name === "ingest_stripe_payment_internal").length,
    2,
  );
});
Deno.test("A04/A25 lifecycle webhook reads current account; stale deauthorization cannot revoke a new authorization", async () => {
  const body = JSON.stringify({
    ...JSON.parse(event()),
    type: "account.application.deauthorized",
    data: { object: { id: "ca_fixture", object: "application" } },
  });
  const active = fixture();
  assert.equal(
    (await stripeWebhookHandler(await signed(body), active.deps)).status,
    200,
  );
  const current = active.calls.find((c) =>
    c.name === "commit_stripe_connection_status_internal"
  )!.args.p_status as Record<string, unknown>;
  assert.equal(current.modelVerified, true);
  assert.equal(current.accessUnavailable, undefined);
  const revoked = fixture({ accountRevoked: true });
  assert.equal(
    (await stripeWebhookHandler(await signed(body), revoked.deps)).status,
    200,
  );
  const missing = revoked.calls.find((c) =>
    c.name === "commit_stripe_connection_status_internal"
  )!.args.p_status as Record<string, unknown>;
  assert.equal(missing.accessUnavailable, true);
  const failed = fixture({ timeout: true });
  assert.equal(
    (await stripeWebhookHandler(await signed(body), failed.deps)).status,
    503,
  );
  assert(
    failed.calls.some((c) =>
      c.name === "fail_stripe_connection_status_internal"
    ),
  );
  assert(
    !failed.calls.some((c) =>
      c.name === "commit_stripe_connection_status_internal"
    ),
  );
});
Deno.test("A09/A14 lost Session response is found after expiry by durable read-only pagination", async () => {
  const { deps, calls, requests } = fixture({
    paid: true,
    expiredUnknown: true,
  });
  assert.equal((await reconcileStripePayments(deps))[0].state, "continuing");
  assert.equal((await reconcileStripePayments(deps))[0].state, "completed");
  assert.equal(
    calls.filter((c) => c.name === "checkpoint_stripe_session_lookup_internal")
      .length,
    1,
  );
  assert(
    requests.some((r) => r.url.includes("starting_after=cs_test_fixture")),
  );
  assert(!requests.some((r) => r.url.endsWith("/checkout/sessions")));
  const facts = calls.find((c) => c.name === "ingest_stripe_payment_internal")!
    .args.p_facts as Record<string, unknown>;
  assert.equal(facts.sessionId, "cs_test_fixture");
  assert.equal((facts.movements as unknown[]).length, 1);
});
Deno.test("A14 exhausted fixed Session search expires an absent attempt without fabricating a Session", async () => {
  const { deps, calls, requests } = fixture({
    expiredUnknown: true,
    missingSession: true,
  });
  assert.equal((await reconcileStripePayments(deps))[0].state, "completed");
  const facts = calls.find((c) => c.name === "ingest_stripe_payment_internal")!
    .args.p_facts as Record<string, unknown>;
  assert.equal(facts.sessionId, null);
  assert.equal(facts.noSessionVerified, true);
  assert.deepEqual(facts.movements, []);
  assert.equal(requests.length, 1);
  assert(requests[0].url.includes("created[gte]="));
  assert.equal(requests[0].key, null);
});
Deno.test("A25 failed provider observation records a durable retry against the claimed lease", async () => {
  const { deps, calls } = fixture({ paid: true, timeout: true });
  assert.equal((await reconcileStripePayments(deps))[0].state, "uncertain");
  const failed = calls.find((c) =>
    c.name === "fail_stripe_reconciliation_internal"
  );
  assert.equal(failed?.args.p_attempt, attempt);
  assert.equal(typeof failed?.args.p_lease, "string");
  assert.equal((await reconcileStripePayments(deps))[0].state, "completed");
});
async function signed(body: string, secret = "whsec_fixture") {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = Array.from(
    new Uint8Array(
      await crypto.subtle.sign(
        "HMAC",
        key,
        new TextEncoder().encode(`${now}.${body}`),
      ),
    ),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  return new Request("https://functions.example/stripe-webhook", {
    method: "POST",
    body,
    headers: { "Stripe-Signature": `t=${now},v1=${signature}` },
  });
}
const event = () =>
  JSON.stringify({
    id: "evt_fixture",
    object: "event",
    account: "acct_fixture",
    livemode: false,
    created: now,
    type: "checkout.session.completed",
    data: {
      object: {
        object: "checkout.session",
        id: session.id,
        client_reference_id: attempt,
      },
    },
  });
Deno.test("A09 timeout retry uses the same durable attempt/key; URL requires committed SQL receipt", async () => {
  const { deps, calls, requests } = fixture({ timeout: true });
  await assert.rejects(() => checkoutStripePayment("a".repeat(64), deps));
  assert.equal(calls.at(-1)?.name, "fail_stripe_checkout_internal");
  const result = await checkoutStripePayment("a".repeat(64), deps);
  assert.equal(result.checkoutUrl, session.url);
  assert.equal(requests[0].key, requests[1].key);
  assert.equal(
    calls.filter((c) => c.name === "claim_stripe_checkout_internal").length,
    2,
  );
  const rejected = fixture({ rejectReceipt: true });
  const response = await stripePaymentHandler(
    new Request("https://functions.example/stripe-checkout", {
      method: "POST",
      body: JSON.stringify({ token: "a".repeat(64) }),
    }),
    rejected.deps,
  );
  assert.equal(response.status, 503);
  assert(!(await response.text()).includes("checkout.stripe.com"));
});
Deno.test("A10 cached completed Session is reconciled, never replaced by a second Session", async () => {
  const { deps, calls, requests } = fixture({ paid: true });
  const result = await checkoutStripePayment("a".repeat(64), deps);
  assert.equal(result.payment.status, "paid");
  assert.equal(result.checkoutUrl, undefined);
  assert.equal(
    requests.filter((r) => r.url.endsWith("/checkout/sessions")).length,
    1,
  );
  const facts = calls.find((c) => c.name === "ingest_stripe_payment_internal")!
    .args.p_facts as Record<string, unknown>;
  assert.equal(
    (facts.movements as Record<string, unknown>[])[0].amountMinor,
    12345,
  );
});
Deno.test("A13 invalid signature never reaches SQL or provider; failed SQL receipt is retryable HTTP", async () => {
  const invalid = fixture({ paid: true });
  const response = await stripeWebhookHandler(
    await signed(event(), "whsec_other"),
    invalid.deps,
  );
  assert.equal(response.status, 400);
  assert.equal(invalid.calls.length, 0);
  assert.equal(invalid.requests.length, 0);
  const rejected = fixture({ paid: true, rejectReceipt: true });
  assert.equal(
    (await stripeWebhookHandler(await signed(event()), rejected.deps)).status,
    503,
  );
  const accepted = fixture({ paid: true });
  assert.equal(
    (await stripeWebhookHandler(await signed(event()), accepted.deps)).status,
    200,
  );
  const payload = accepted.calls.find((c) =>
    c.name === "ingest_stripe_payment_internal"
  )!.args.p_event as Record<string, unknown>;
  assert.match(payload.bodyHash as string, /^[a-f0-9]{64}$/);
});
Deno.test("A08 return observation cannot dispatch or obtain a new pay capability", async () => {
  const { deps, calls, requests } = fixture();
  const response = await stripePaymentHandler(
    new Request("https://functions.example/stripe-return", {
      method: "POST",
      body: JSON.stringify({ token: "b".repeat(64) }),
    }),
    deps,
    true,
  );
  assert.equal(response.status, 200);
  assert.deepEqual(calls.map((c) => c.name), ["read_stripe_return_internal"]);
  assert.equal(requests.length, 0);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
  assert.equal(
    (await stripePaymentHandler(
      new Request("https://functions.example/stripe-checkout", {
        method: "POST",
        headers: { Origin: "https://foreign.example" },
        body: "{}",
      }),
      deps,
    )).status,
    403,
  );
});

Deno.test("A08/A25 historical recovery survives removed encrypted capability sources", async () => {
  const { deps, requests } = fixture({ paid: true });
  deps.openSource = () => {
    throw new Error("expired source must never be opened");
  };
  assert.equal((await reconcileStripePayments(deps))[0].state, "completed");
  assert.equal(
    requests.filter((r) => r.url.endsWith("/checkout/sessions")).length,
    0,
  );
});

Deno.test("A08/A20 handoff scope reads safely, consumes once and never returns order_pay", async () => {
  const { deps, requests } = fixture();
  const rpc = deps.rpc;
  let consumed = false;
  deps.rpc = async (name, args) => {
    if (name !== "read_stripe_handoff_internal") return rpc(name, args);
    assert.equal(args.p_token, "c".repeat(64));
    if (!args.p_consume) {
      return {
        payment: {
          method: "stripe",
          status: "open",
          allowedActions: consumed ? ["refresh"] : ["pay", "refresh"],
        },
      };
    }
    if (consumed) throw new Error("INVALID_CAPABILITY");
    consumed = true;
    return { source: {} };
  };
  const observed = await checkoutStripeHandoff("c".repeat(64), deps, false);
  assert.equal(requests.length, 0);
  assert(!JSON.stringify(observed).includes("token"));
  const prepared = await checkoutStripeHandoff("c".repeat(64), deps, true);
  assert(prepared.checkoutUrl);
  assert(!JSON.stringify(prepared).includes("a".repeat(64)));
  const before = requests.length;
  await assert.rejects(() => checkoutStripeHandoff("c".repeat(64), deps, true));
  assert.equal(requests.length, before);
  assert.deepEqual(
    (await checkoutStripeHandoff("c".repeat(64), deps, false)).payment
      .allowedActions,
    ["refresh"],
  );
});

Deno.test("A20 embedded creation prepares Checkout before delayed handoff without disclosing either write scope", async () => {
  const { deps, calls, requests } = fixture();
  const rpc = deps.rpc;
  deps.rpc = async (name, args) =>
    name === "attach_stripe_handoff_internal"
      ? (calls.push({ name, args }), null)
      : await rpc(name, args);
  const result = await prepareStripeOrderDelivery(
    { sealed: {}, payBaseUrl: "https://tickets.example/stripe/pay" },
    1,
    attempt,
    "embed",
    {},
    deps,
  );
  assert.equal(
    requests.filter((r) => r.url.endsWith("/checkout/sessions")).length,
    1,
  );
  assert(
    calls.some((c) => c.name === "commit_stripe_checkout_session_internal"),
  );
  const access = result.payment_access as Record<string, string>;
  assert.equal(access.kind, "handoff");
  assert(access.url.endsWith("#handoff=" + access.token));
  assert.notEqual(access.token, "a".repeat(64));
  assert(!JSON.stringify(result).includes("checkout.stripe.com"));
  assert(!JSON.stringify(result).includes("a".repeat(64)));
  assert(!JSON.stringify(result).includes("b".repeat(64)));
});
Deno.test("A09/A20 embedded dispatch timeout preserves the same handoff and recoverable attempt", async () => {
  const { deps, calls } = fixture({ timeout: true });
  const rpc = deps.rpc;
  deps.rpc = async (name, args) =>
    name === "attach_stripe_handoff_internal"
      ? (calls.push({ name, args }), null)
      : await rpc(name, args);
  const source = {
    sealed: {},
    payBaseUrl: "https://tickets.example/stripe/pay",
  };
  const first = await prepareStripeOrderDelivery(
    source,
    1,
    attempt,
    "embed",
    {},
    deps,
  );
  assert(calls.some((c) => c.name === "fail_stripe_checkout_internal"));
  const next = await prepareStripeOrderDelivery(
    source,
    1,
    attempt,
    "embed",
    {},
    deps,
  );
  assert.deepEqual(first.payment_access, next.payment_access);
  assert(!("checkout_url" in next));
});
Deno.test("A05 web creation retains its private pay source and prepared Checkout", async () => {
  const { deps } = fixture();
  const result = await prepareStripeOrderDelivery(
    { sealed: {}, payBaseUrl: "https://tickets.example/stripe/pay" },
    1,
    attempt,
    "web",
    {},
    deps,
  );
  assert.equal(result.checkout_url, session.url);
  assert.equal(
    (result.payment_access as Record<string, string>).token,
    "a".repeat(64),
  );
});
