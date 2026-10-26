import { strict as assert } from "node:assert";
import {
  accountReadiness,
  type CheckoutSnapshot,
  StripeBoundaryError,
  StripeProvider,
  toMinorUnits,
  verifyStripeEvent,
} from "./provider.ts";
const NOW = 1_790_000_000;
const attempt: CheckoutSnapshot = {
  attemptId: "attempt_0001",
  accountId: "acct_organizer",
  livemode: false,
  amountMinor: 123450,
  currency: "CZK",
  orderReference: "Order 1234",
  createdAt: NOW,
  expiresAt: NOW + 1900,
  idempotencyKey: "festapp:attempt_0001",
  returnUrl: `https://tickets.example/stripe/return?return_handle=${
    "a".repeat(64)
  }`,
};
const session = (patch: Record<string, unknown> = {}) => ({
  id: "cs_test_example",
  object: "checkout.session",
  livemode: false,
  mode: "payment",
  amount_total: attempt.amountMinor,
  currency: "czk",
  client_reference_id: attempt.attemptId,
  expires_at: attempt.expiresAt,
  payment_method_types: ["card"],
  status: "open",
  payment_status: "unpaid",
  url: "https://checkout.stripe.com/c/pay/cs_test_example",
  ...patch,
});
function provider(fetcher: typeof fetch, patch: Record<string, unknown> = {}) {
  return new StripeProvider({
    secretKey: "sk_test_fixtureOnly",
    livemode: false,
    apiVersion: "2025-06-30.basil",
    allowedReturnOrigins: ["https://tickets.example"],
    now: () => NOW,
    fetch: fetcher,
    ...patch,
  });
}
const rejects = async (work: () => Promise<unknown>, code: string) => {
  await assert.rejects(
    work,
    (e: unknown) => e instanceof StripeBoundaryError && e.code === code,
  );
};
Deno.test("A01 platform verification uses the actual key owner without connected-account impersonation", async () => {
  const p = provider(async (input, init) => {
    assert.equal(String(input), "https://api.stripe.com/v1/account");
    assert.equal(new Headers(init?.headers).has("Stripe-Account"), false);
    return Response.json({ object: "account", id: "acct_platform" });
  });
  await p.verifyPlatform("acct_platform");
  await rejects(
    () => p.verifyPlatform("acct_wrong"),
    "stripe_platform_mismatch",
  );
});
Deno.test("A05 exact minor units, zero and three-decimal currencies; no rounding or float coercion", () => {
  assert.equal(toMinorUnits("1234.50", "CZK"), 123450);
  assert.equal(toMinorUnits("0.01", "EUR"), 1);
  assert.equal(toMinorUnits("123", "JPY"), 123);
  assert.equal(toMinorUnits("1.234", "KWD"), 1234);
  for (
    const invalid of [
      "1.001",
      "1e2",
      "-1",
      " 1",
      "NaN",
      "01",
      "1,25",
      "9007199254740992",
    ]
  ) {
    assert.throws(() => toMinorUnits(invalid, "CZK"), StripeBoundaryError);
  }
  assert.throws(() => toMinorUnits("1", "XXX"), StripeBoundaryError);
});
Deno.test("A04 charges and payouts are distinct; full Dashboard and liability must be explicit", () => {
  const account = {
    id: "acct_organizer",
    object: "account",
    charges_enabled: true,
    payouts_enabled: false,
    capabilities: { card_payments: "active" },
    controller: {
      fees: { payer: "account" },
      losses: { payments: "stripe" },
      stripe_dashboard: { type: "full" },
    },
  };
  const ready = accountReadiness(account, "acct_organizer");
  assert.equal(ready.ready, true);
  assert.equal(ready.payoutsEnabled, false);
  assert.equal(
    accountReadiness({ ...account, controller: {} }, "acct_organizer").ready,
    false,
  );
  assert.throws(
    () => accountReadiness(account, "acct_foreign"),
    StripeBoundaryError,
  );
});
Deno.test("A05/A09 direct Checkout uses immutable SQL price, account scope and stable idempotence", async () => {
  const requests: { url: string; headers: Headers; body: URLSearchParams }[] =
    [];
  const client = provider(async (url, init) => {
    requests.push({
      url: String(url),
      headers: new Headers(init?.headers),
      body: new URLSearchParams(String(init?.body)),
    });
    return Response.json(session());
  });
  await client.createCheckout(attempt);
  await client.createCheckout(attempt);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].headers.get("Stripe-Account"), attempt.accountId);
  assert.equal(
    requests[0].headers.get("Idempotency-Key"),
    requests[1].headers.get("Idempotency-Key"),
  );
  assert.equal(requests[0].body.toString(), requests[1].body.toString());
  assert.equal(
    requests[0].body.get("line_items[0][price_data][unit_amount]"),
    "123450",
  );
  assert.equal(requests[0].body.get("payment_method_types[0]"), "card");
  for (const key of requests[0].body.keys()) {
    assert(
      !/transfer|application_fee|customer_email|answers|adjustable_quantity/
        .test(key),
    );
  }
  assert.equal(requests[0].body.get("adaptive_pricing[enabled]"), "false");
});
Deno.test("A09 timeout remains retryable without rotating key; uncertain old attempt never dispatched", async () => {
  let calls = 0;
  const client = provider(() => {
    calls++;
    throw new Error("do not expose provider secrets");
  });
  await rejects(
    () => client.createCheckout(attempt),
    "provider_temporarily_unavailable",
  );
  await rejects(
    () => client.createCheckout({ ...attempt, createdAt: NOW - 24 * 3600 }),
    "checkout_requires_reconciliation",
  );
  assert.equal(calls, 1);
});
Deno.test("A07/A13 reject changed server snapshot, environment and unsafe redirect before dispatch", async () => {
  let calls = 0;
  const client = provider(async () => {
    calls++;
    return Response.json(session());
  });
  for (
    const patch of [{ livemode: true }, { amountMinor: 1.1 }, {
      currency: "XXX",
    }, { accountId: "acct_x\r\nInjected:1" }]
  ) {
    await rejects(
      () => client.createCheckout({ ...attempt, ...patch }),
      "stripe_snapshot_invalid",
    );
  }
  for (
    const url of [
      "https://evil.example/return",
      "https://tickets.example/return#token",
      "https://tickets.example/return?token=secret",
      "https://user:password@tickets.example/return",
    ]
  ) {
    await rejects(
      () => client.createCheckout({ ...attempt, returnUrl: url }),
      "stripe_return_origin_invalid",
    );
  }
  await rejects(
    () => client.createCheckout({ ...attempt, expiresAt: NOW + 1799 }),
    "reservation_checkout_window_invalid",
  );
  assert.equal(calls, 0);
});
Deno.test("A13 provider response must match account-scoped immutable Session snapshot", async () => {
  for (
    const patch of [
      { amount_total: 1 },
      { currency: "eur" },
      { livemode: true },
      { client_reference_id: "foreign" },
      { expires_at: NOW + 9000 },
      { payment_method_types: ["card", "klarna"] },
    ]
  ) {
    await rejects(
      () =>
        provider(async () => Response.json(session(patch))).createCheckout(
          attempt,
        ),
      "stripe_session_mismatch",
    );
  }
  await rejects(
    () =>
      provider(async () =>
        Response.json(
          session({ url: "https://checkout.stripe.com.evil.example/" }),
        )
      ).createCheckout(attempt),
    "provider_response_invalid",
  );
});
Deno.test("A10 return status and checkout.session.completed do not constitute payment confirmation", async () => {
  const result = await provider(async (url) => {
    assert(String(url).includes("expand[]=payment_intent"));
    return Response.json(
      session({ status: "complete", payment_status: "unpaid" }),
    );
  }).session(attempt, "cs_test_example");
  assert.equal(result.payment_status, "unpaid");
});
Deno.test("A25 rate limits and 5xx are retryable; errors never reveal raw provider details", async () => {
  for (const status of [429, 500, 503, 400, 401]) {
    try {
      await provider(async () =>
        new Response("secret provider body", { status })
      ).createCheckout(attempt);
      assert.fail();
    } catch (e) {
      assert(e instanceof StripeBoundaryError);
      assert.equal(e.retryable, status === 429 || status >= 500);
      assert(!e.message.includes("secret"));
    }
  }
});
const secret = "whsec_fixtureOnlyNotReal";
const event = {
  id: "evt_example",
  account: "acct_organizer",
  livemode: false,
  type: "checkout.session.completed",
  created: NOW,
  data: { object: session() },
};
async function signed(raw: Uint8Array, timestamp = NOW) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const prefix = new TextEncoder().encode(`${timestamp}.`);
  const input = new Uint8Array(prefix.length + raw.length);
  input.set(prefix);
  input.set(raw, prefix.length);
  const digest = await crypto.subtle.sign("HMAC", key, input);
  const hex = Array.from(
    new Uint8Array(digest),
    (b) => b.toString(16).padStart(2, "0"),
  ).join("");
  return `t=${timestamp},v1=${hex}`;
}
Deno.test("A13 raw signature, rotation, replay tolerance and environment validation", async () => {
  const raw = new TextEncoder().encode(JSON.stringify(event));
  const signature = await signed(raw);
  assert.equal(
    (await verifyStripeEvent(
      raw,
      `${signature},v1=${"0".repeat(64)}`,
      secret,
      false,
      NOW,
    )).id,
    event.id,
  );
  await rejects(
    () =>
      verifyStripeEvent(
        new TextEncoder().encode(JSON.stringify(event, null, 2)),
        signature,
        secret,
        false,
        NOW,
      ),
    "stripe_signature_invalid",
  );
  await rejects(
    () => verifyStripeEvent(raw, signature, secret, true, NOW),
    "stripe_event_invalid",
  );
  await rejects(
    () => verifyStripeEvent(raw, signature, secret, false, NOW + 301),
    "stripe_signature_invalid",
  );
  await rejects(
    () => verifyStripeEvent(raw, `${signature},t=${NOW}`, secret, false, NOW),
    "stripe_signature_invalid",
  );
  const platform = new TextEncoder().encode(
    JSON.stringify({ ...event, account: undefined }),
  );
  const platformSignature = await signed(platform);
  await rejects(
    () => verifyStripeEvent(platform, platformSignature, secret, false, NOW),
    "stripe_event_invalid",
  );
});
Deno.test("A13 correctly signed malformed facts are rejected before ingestion", async () => {
  for (
    const patch of [{ created: -1 }, { data: { object: [] } }, {
      account: "acct_other\r\n",
    }]
  ) {
    const raw = new TextEncoder().encode(
      JSON.stringify({ ...event, ...patch }),
    );
    const signature = await signed(raw);
    await rejects(
      () => verifyStripeEvent(raw, signature, secret, false, NOW),
      "stripe_event_invalid",
    );
  }
});
Deno.test("A09 timeout replay keeps original Session expiry after the 30 minute creation window", async () => {
  let calls = 0;
  const client = provider(async (_url, init) => {
    calls++;
    assert.equal(
      new URLSearchParams(String(init?.body)).get("expires_at"),
      String(attempt.expiresAt),
    );
    return Response.json(session());
  }, { now: () => NOW + 200 });
  await client.createCheckout(attempt);
  assert.equal(calls, 1);
  await rejects(
    () =>
      provider(async () => Response.json(session()), {
        now: () => attempt.expiresAt,
      }).createCheckout(attempt),
    "reservation_expired",
  );
});
Deno.test("A16/A25 refund recovery is account-scoped, bounded and keeps a provider cursor", async () => {
  const client = provider(async (url, init) => {
    assert.equal(
      new Headers(init?.headers).get("Stripe-Account"),
      attempt.accountId,
    );
    assert.match(
      String(url),
      /payment_intent=pi_fixture&limit=100&starting_after=re_before/,
    );
    return Response.json({
      data: [{ id: "re_after", object: "refund" }],
      has_more: true,
    });
  });
  assert.equal(
    (await client.refunds(attempt, "pi_fixture", "re_before")).nextCursor,
    "re_after",
  );
  await rejects(
    () => client.refunds(attempt, "pi_fixture", "re_x&account=foreign"),
    "stripe_request_invalid",
  );
  await rejects(
    () =>
      provider(async () => Response.json({ data: [], has_more: true })).refunds(
        attempt,
        "pi_fixture",
      ),
    "provider_response_invalid",
  );
});
Deno.test("loopback return origins are confined to sandbox and cannot enter live configuration", () => {
  provider(async () => Response.json(session()), {
    allowedReturnOrigins: ["http://127.0.0.1:61171"],
  });
  assert.throws(
    () =>
      new StripeProvider({
        secretKey: "sk_live_fixtureOnly",
        livemode: true,
        apiVersion: "2025-06-30.basil",
        allowedReturnOrigins: ["http://127.0.0.1:61171"],
      }),
    StripeBoundaryError,
  );
});

Deno.test('tenant Checkout locale is explicit while legacy attempts preserve their original body', async () => {
  const bodies: URLSearchParams[] = [];
  const p = provider(async (_url, init) => {
    bodies.push(new URLSearchParams(String(init?.body)));
    return Response.json(session());
  });
  await p.createCheckout({ ...attempt, locale: 'en' });
  await p.createCheckout({ ...attempt, locale: 'auto' });
  assert.equal(bodies[0].get('locale'), 'en');
  assert.equal(bodies[1].has('locale'), false);
  assert.equal(bodies[0].get('line_items[0][price_data][unit_amount]'), String(attempt.amountMinor));
});
