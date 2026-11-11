import { strict as assert } from "node:assert";
import type { DispatchClaim, HostedPaymentDependencies } from "./contracts.ts";
import { reconcilePayments } from "./reconcile.ts";

function fixture() {
  const calls: string[] = [];
  let elapsed = 0;
  const claim: DispatchClaim = {
    providerId: "different_gateway",
    disposition: "dispatch",
    lease: "owned-lease",
    checkoutId: "checkout/42",
    connectorState: {},
    source: null,
    returnBaseUrl: "https://tickets.example/payments/return",
    snapshot: {
      attemptId: "attempt-42",
      accountId: "merchant-42",
      livemode: false,
      amountMinor: 12345,
      currency: "CZK",
      orderReference: "42",
      createdAt: 1,
      expiresAt: 2,
      idempotencyKey: "immutable-command-42",
    },
  };
  const deps: HostedPaymentDependencies = {
    livemode: false,
    allowedOrigins: ["https://tickets.example"],
    routes: { payPath: "/payments/pay", returnPath: "/payments/return" },
    verifyPlatform: async () => {},
    openSource: () => {
      throw new Error("unexpected secret read");
    },
    connector: {
      id: claim.providerId,
      displayName: "Different gateway",
      validateCheckoutUrl: (value) => value,
      createOrRecoverCheckout: () => {
        throw new Error("unexpected create");
      },
      checkout: () => {
        throw new Error("unexpected checkout");
      },
      recoverCheckout: async () => {
        calls.push("recover");
        return { kind: "found", checkoutId: "checkout/42" };
      },
      observePayment: async () => {
        calls.push("observe");
        return {
          checkoutId: "checkout/42",
          paymentId: "money/42",
          checkoutStatus: "complete",
          movements: [{
            providerId: "money/42",
            kind: "payment",
            amountMinor: 12345,
            currency: "CZK",
            occurredAt: 1,
          }],
          disputes: [],
        };
      },
    },
    store: {
      recoverableAttempts:
        async () => [{ attemptId: "attempt-42", accountId: "merchant-42" }],
      claimSync: async () => claim,
      failSync: async () => {
        calls.push("release");
      },
      ingest: async () => {
        calls.push("ingest");
        return {
          committed: true,
          payment: { method: claim.providerId, status: "paid" },
        };
      },
      purgeExpiredSources: async () => {
        calls.push("purge");
        return 0;
      },
      claimCheckout: () => {
        throw new Error("unexpected checkout claim");
      },
      commitCheckout: () => {
        throw new Error("unexpected checkout commit");
      },
      failCheckout: async () => {},
      deferRecovery: async () => {},
      readReturn: async () => ({}),
      readStatus: async () => ({}),
      readHandoff: async () => ({}),
      attachHandoff: async () => {},
    },
    maintenance: {
      recoverableConnections: async () => [{
        connectionId: "connection-42",
        accountId: "merchant-42",
      }],
      observeConnection: async () => {
        calls.push("connection");
        elapsed += 46_000;
      },
    },
  };
  return {
    deps,
    claim,
    calls,
    now: () => elapsed,
    advance: (milliseconds: number) => {
      elapsed += milliseconds;
    },
  };
}

Deno.test("failed cleanup and account queue do not suppress verified payment recovery", async () => {
  const f = fixture();
  f.deps.store.purgeExpiredSources = async () => {
    throw new Error("private cleanup failure");
  };
  const deps = {
    ...f.deps,
    maintenance: {
      ...f.deps.maintenance!,
      recoverableConnections: async () => {
        throw new Error("private connection failure");
      },
    },
  };
  const results = await reconcilePayments(deps, f.now);
  assert(
    results.some((r) =>
      r.attemptId === "attempt-42" && r.state === "completed"
    ),
  );
  assert.equal(results.filter((r) => r.state === "uncertain").length, 2);
  assert.equal(f.calls.filter((c) => c === "ingest").length, 1);
});

Deno.test("account maintenance cannot consume the budget before payment recovery", async () => {
  const f = fixture();
  const results = await reconcilePayments(f.deps, f.now);
  assert.equal(results[0].attemptId, "attempt-42");
  assert.equal(results[0].state, "completed");
  assert(f.calls.indexOf("ingest") < f.calls.indexOf("connection"));
});

for (const mismatch of ["attempt", "account", "provider"] as const) {
  Deno.test(`a foreign ${mismatch} claim never reaches a provider or releases an unrelated lease`, async () => {
    const f = fixture();
    f.deps.store.claimSync = async () => ({
      ...f.claim,
      providerId: mismatch === "provider" ? "foreign" : f.claim.providerId,
      snapshot: {
        ...f.claim.snapshot,
        attemptId: mismatch === "attempt"
          ? "foreign-attempt"
          : f.claim.snapshot.attemptId,
        accountId: mismatch === "account"
          ? "foreign-account"
          : f.claim.snapshot.accountId,
      },
    });
    const results = await reconcilePayments(f.deps, f.now);
    assert(
      results.some((r) =>
        r.attemptId === "attempt-42" && r.state === "uncertain"
      ),
    );
    assert(!f.calls.includes("recover"));
    assert(!f.calls.includes("ingest"));
    assert(!f.calls.includes("release"));
  });
}

Deno.test("a slow claim cannot start remote financial work after the recovery budget expires", async () => {
  const f = fixture();
  f.deps.store.claimSync = async () => {
    f.advance(46_000);
    return f.claim;
  };
  const results = await reconcilePayments(f.deps, f.now);
  assert.deepEqual(results, [{ attemptId: "attempt-42", state: "continuing" }]);
  assert(f.calls.includes("release"));
  assert(!f.calls.includes("recover"));
  assert(!f.calls.includes("ingest"));
});
Deno.test("failure to load payment work still allows independent account maintenance", async () => {
  const f = fixture();
  f.deps.store.recoverableAttempts = async () => {
    throw new Error("private queue failure");
  };
  const results = await reconcilePayments(f.deps, f.now);
  assert(
    results.some((r) =>
      r.operation === "read_attempts" && r.state === "uncertain"
    ),
  );
  assert(
    results.some((r) =>
      r.connectionId === "connection-42" && r.state === "completed"
    ),
  );
  assert(!f.calls.includes("ingest"));
});
