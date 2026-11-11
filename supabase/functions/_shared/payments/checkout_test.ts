import { strict as assert } from "node:assert";
import { checkoutPayment, recoverPaymentClaim } from "./checkout.ts";
import {
  type CheckoutSnapshot,
  type HostedPaymentDependencies,
  PaymentError,
  type PaymentObservation,
  type PaymentClaim,
  type RecoveryResult,
} from "./contracts.ts";
import { PaymentRegistry, registeredPaymentHandler } from "./registry.ts";
import { prepareOrderDelivery } from "./orderDelivery.ts";

function fixture(id = "different_gateway") {
  const snapshot = {
    attemptId: "12345678-1234-4234-8234-123456789abc",
    accountId: "merchant/42",
    livemode: false,
    amountMinor: 12345,
    currency: "CZK",
    orderReference: "ABC",
    createdAt: 1,
    expiresAt: Math.floor(Date.now() / 1000) + 1860,
    idempotencyKey: "saved-attempt-key",
    returnBaseUrl: "https://tickets.example/payments/return",

  };
  const claim = {
    providerId: id,
    disposition: "dispatch" as const,
    returnBaseUrl: snapshot.returnBaseUrl,
    checkoutId: null,
    connectorState: {},
    lease: "saved-lease",
    snapshot,
    source: {},
  };
  const calls: string[] = [];
  const observed: PaymentObservation[] = [];
  const dispatched: CheckoutSnapshot[] = [];
  const checkout = {
    id: "checkout/42",
    status: "open" as const,
    url: "https://pay.example/checkout/42",
    expiresAt: snapshot.expiresAt,
  };
  const deps: HostedPaymentDependencies = {
    livemode: false,
    allowedOrigins: ["https://tickets.example"],
    routes: { payPath: "/payments/pay", returnPath: "/payments/return" },
    verifyPlatform: async () => {
      calls.push("verify");
    },
    openSource: async () => ({
      payToken: "a".repeat(64),
      returnHandle: "b".repeat(64),
    }),
    connector: {
      id,
      displayName: "Other gateway",
      validateCheckoutUrl: (value) => {
        const url = new URL(value);
        if (
          url.origin !== "https://pay.example" || url.username || url.password
        ) throw new PaymentError("unsafe_redirect");
        return url.toString();
      },
      createOrRecoverCheckout: async (value) => {
        dispatched.push(value);
        return checkout;
      },
      checkout: async () => checkout,
      recoverCheckout: async (_claim, saved) => {
        if (Math.floor(Date.now()/1000) >= saved.expiresAt)
          return {kind: "unresolved", reason: "no_lookup_api", retryAfterSeconds: 120};
        return {kind: "found", checkoutId: (await deps.connector.createOrRecoverCheckout(saved)).id};
      },
      observePayment: async (_snapshot, checkoutId) => ({
        checkoutId,
        paymentId: "settlement/42",
        checkoutStatus: "complete",
        movements: [{
          providerId: "money/42",
          kind: "payment",
          amountMinor: 12345,
          currency: "CZK",
          occurredAt: 1,
        }],
        disputes: [],
      }),
    },
    store: {
      claimCheckout: async () => claim,
      commitCheckout: async (s, lease, value) => {
        assert.equal(s.attemptId, snapshot.attemptId);
        assert.equal(lease, claim.lease);
        assert.equal(value.id, checkout.id);
        calls.push("commit");
        return { committed: true as const, payment: { method: id, status: "open" } };
      },
      failCheckout: async () => {
        calls.push("fail");
      },
      ingest: async (_snapshot, lease, _event, observation) => {
        assert.equal(lease, claim.lease);
        observed.push(observation);
        return {
            committed: true as const,
            payment: {
              method: id,
              status: observation.noCheckoutVerified ? "expired" : "paid",
            },
        };
      },
      deferRecovery: async () => { calls.push("defer"); },
      readReturn: async () => ({ method: id, status: "paid" }),
      readStatus: async () => ({ method: id, status: "open" }),
      readHandoff: async () => ({ source: {} }),
      attachHandoff: async () => {
        calls.push("handoff");
      },
      purgeExpiredSources: async () => 0,
      recoverableAttempts: async () => [],
      claimSync: async () => claim,
      failSync: async () => {},
    },
  };
  return { deps, snapshot, claim, calls, observed, dispatched, checkout };
}

Deno.test("a registered non-Stripe connector executes the actual checkout engine and HTTP entrypoint", async () => {
  const f = fixture(),
    registry = new PaymentRegistry([[f.deps.connector.id, () => f.deps]]);
  const response = await registeredPaymentHandler(
    new Request("https://api.example/payment-checkout", {
      method: "POST",
      body: JSON.stringify({
        provider: f.deps.connector.id,
        token: "a".repeat(64),
      }),
    }),
    registry,
  );
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    payment: { method: "different_gateway", status: "open" },
    checkoutUrl: "https://pay.example/checkout/42",
  });
  assert.equal(f.dispatched[0].accountId, "merchant/42");
  assert.equal(
    f.dispatched[0].returnUrl,
    "https://tickets.example/payments/return?return_handle=" + "b".repeat(64),
  );
});

Deno.test("provider registry has no default, duplicate names or cross-provider binding", async () => {
  const f = fixture();
  assert.throws(
    () => new PaymentRegistry([["x", () => f.deps], ["x", () => f.deps]]),
    PaymentError,
  );
  const registry = new PaymentRegistry([["wrong", () => f.deps]]);
  assert.throws(() => registry.resolve("wrong"), /identity_mismatch/);
  assert.throws(() => registry.resolve(undefined), /unavailable/);
  const response = await registeredPaymentHandler(
    new Request("https://api.example", {
      method: "POST",
      body: JSON.stringify({ provider: "uninstalled", token: "a".repeat(64) }),
    }),
    registry,
  );
  assert.equal(response.status, 400);
  assert.equal(f.dispatched.length, 0);
});

Deno.test("busy/read claims never dispatch or refresh a provider checkout", async () => {
  for (const disposition of ["busy", "read"]) {
    const f = fixture();
    f.deps.store.claimCheckout = async () => ({providerId: f.deps.connector.id, disposition: disposition as "read" | "busy", payment: {}});
    assert.deepEqual(await checkoutPayment("a".repeat(64), f.deps), {
      payment: {},
    });
    assert.equal(f.dispatched.length, 0);
  }
});

Deno.test("uncertain dispatch preserves the saved identity and releases its lease", async () => {
  const f = fixture();
  let first = true;
  const deps = {
    ...f.deps,
    connector: {
      ...f.deps.connector,
      createOrRecoverCheckout: async (s: CheckoutSnapshot) => {
        f.dispatched.push(s);
        if (first) {
          first = false;
          throw new Error("timeout");
        }
        return f.checkout;
      },
    },
  };
  await assert.rejects(() => checkoutPayment("a".repeat(64), deps), /timeout/);
  assert(f.calls.includes("fail"));
  await recoverPaymentClaim(f.claim, deps);
  assert.equal(f.dispatched.length, 2);
  assert.equal(f.dispatched[0].idempotencyKey, f.dispatched[1].idempotencyKey);
  assert.equal(f.dispatched[0].expiresAt, f.dispatched[1].expiresAt);
  assert.equal(f.observed[0].movements[0].providerId, "money/42");
});

Deno.test("a provider without lookup or remote expiry stays unresolved after the inventory deadline", async () => {
  const f = fixture(); f.snapshot.expiresAt = 2;
  assert.equal((await recoverPaymentClaim(f.claim, f.deps)).reconciliationPending, true);
  assert.equal(f.observed.length, 0); assert.equal(f.dispatched.length, 0);
  assert(f.calls.includes("defer"));
});
Deno.test("only an explicit provider absence guarantee can commit absence", async () => {
  const f = fixture(); f.snapshot.expiresAt = 2;
  f.deps.connector.recoverCheckout = async (): Promise<RecoveryResult> => ({kind: "definitively_absent", evidence: "test protocol: authoritative command receipt says rejected before creation"});
  assert.equal((await recoverPaymentClaim(f.claim, f.deps)).status, "expired");
  assert.equal(f.observed[0].noCheckoutVerified, true);
});
Deno.test("partial lookup leaves no fabricated observation and a persisted checkpoint is not deferred twice", async () => {
  const f = fixture(); f.snapshot.expiresAt = 2;
  f.deps.connector.recoverCheckout = async () => ({kind: "unresolved", reason: "page_pending", retryAfterSeconds: 10, checkpointed: true});
  assert.equal((await recoverPaymentClaim(f.claim, f.deps)).reconciliationPending, true);
  assert.equal(f.observed.length, 0); assert(!f.calls.includes("defer"));
});

Deno.test("unsafe checkout redirects, wrong mode and foreign receipts fail closed", async () => {
  const f = fixture();
  await assert.rejects(
    () =>
      checkoutPayment("a".repeat(64), {
        ...f.deps,
        connector: {
          ...f.deps.connector,
          createOrRecoverCheckout: async () => ({
            ...f.checkout,
            url: "https://evil.example",
          }),
        },
      }),
    /unsafe_redirect/,
  );
  assert(!f.calls.includes("commit"));
  await assert.rejects(
    () => checkoutPayment("a".repeat(64), { ...f.deps, livemode: true }),
    /dispatch_invalid/,
  );
  await assert.rejects(
    () =>
      checkoutPayment("a".repeat(64), {
        ...f.deps,
        store: {
          ...f.deps.store,
          commitCheckout: async () => ({
            committed: true as const,
            payment: { method: "another_provider", status: "open" },
          }),
        },
      }),
    /provider_mismatch/,
  );
});

Deno.test("embedding gives only a one-use handoff and still prepares the same checkout", async () => {
  const f = fixture();
  const result = await prepareOrderDelivery(
    { sealed: {}, payBaseUrl: "https://tickets.example/payments/pay" },
    1,
    f.snapshot.attemptId,
    "embed",
    {},
    f.deps,
  );
  const access = result.payment_access as {
    token: string;
    url: string;
    kind: string;
  };
  assert.equal(access.kind, "handoff");
  assert.notEqual(access.token, "a".repeat(64));
  assert.equal(result.checkout_url, undefined);
  assert(f.calls.includes("handoff"));
  assert.equal(f.dispatched.length, 1);
});

Deno.test("connection dispatch preserves authentication and origin but strips client routing metadata", async () => {
  const f = fixture();
  let seen = false;
  const binding = {
    ...f.deps,
    connection: {
      handle: async (request: Request) => {
        assert.equal(request.headers.get("Authorization"), "Bearer fixture");
        assert.equal(request.headers.get("Origin"), "https://tickets.example");
        assert.deepEqual(await request.json(), {
          action: "status",
          unitId: 42,
        });
        seen = true;
        return Response.json({ ready: false });
      },
    },
  };
  const registry = new PaymentRegistry([[f.deps.connector.id, () => binding]]);
  const response = await registeredPaymentHandler(
    new Request("https://api.example/payment-connect", {
      method: "POST",
      headers: {
        Authorization: "Bearer fixture",
        Origin: "https://tickets.example",
      },
      body: JSON.stringify({
        provider: f.deps.connector.id,
        action: "status",
        unitId: 42,
      }),
    }),
    registry,
    "connect",
  );
  assert.equal(response.status, 200);
  assert(seen);
});

Deno.test('unconfigured connector returns the public configuration error without leaking failures', async () => {
  const registry = new PaymentRegistry([["other", () => { throw new Error("other_not_configured"); }]]);
  const request = () => new Request("https://api.example/payment-connect", {
    method: "POST", body: JSON.stringify({ provider: "other", action: "status" }),
  });
  const response = await registeredPaymentHandler(request(), registry, "connect");
  assert.equal(response.status, 503);
  assert.equal(response.headers.get("Access-Control-Allow-Origin"), "*");
  assert.deepEqual(await response.json(), { error: "other_not_configured" });
  const broken = new PaymentRegistry([["other", () => { throw new Error("private credential failure"); }]]);
  assert.deepEqual(await (await registeredPaymentHandler(request(), broken, "connect")).json(), {
    error: "payment_temporarily_unavailable",
  });
});
