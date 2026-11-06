import { strict as assert } from "node:assert";
import success from "./fixtures/succeeded.json" with { type: "json" };
import expired from "./fixtures/expired.json" with { type: "json" };
import partial from "./fixtures/partial-refund.json" with { type: "json" };
import { barionFacts } from "./facts.ts";
import { barionPaymentAdapter, BarionPaymentConnector } from "./adapter.ts";
import { BarionSandboxProvider } from "./provider.ts";
import { checkoutPayment, recoverPaymentClaim } from "../payments/checkout.ts";
import { type CheckoutSnapshot } from "../payments/contracts.ts";
const snapshot: CheckoutSnapshot = {
  attemptId: success.PaymentRequestId,
  accountId: "sandbox-fixture",
  livemode: false,
  amountMinor: 100,
  currency: "CZK",
  orderReference: "Sandbox fixture",
  createdAt: Math.floor(Date.parse("2026-11-06T12:18:38Z") / 1000),
  expiresAt: Math.floor(Date.parse("2026-11-06T12:49:38Z") / 1000),
  idempotencyKey: success.PaymentRequestId,
};
const id = success.PaymentId;
function provider(state: unknown = success) {
  return new BarionSandboxProvider({
    accountId: snapshot.accountId,
    posKey: "12345678123442348234123456789abc",
    payee: "merchant@example.test",
    callbackUrl: "https://callback.example.test/hint",
    allowedReturnOrigins: ["https://tickets.example.test"],
    fetch: () => Promise.resolve(Response.json(state)),
  });
}
const copy = () => JSON.parse(JSON.stringify(success));
Deno.test("Barion recorded sandbox payment uses completion time and excludes processor fee", () => {
  const f = barionFacts(snapshot, id, success);
  assert.equal(f.movements.length, 1);
  assert.equal(f.movements[0].amountMinor, 100);
  assert.equal(
    f.movements[0].occurredAt,
    Math.ceil(Date.parse(success.CompletedAt) / 1000),
  );
  assert.equal(f.disputes.length, 0);
});
Deno.test("Barion recorded external partial refund is distinct while payment stays Succeeded", () => {
  const f = barionFacts(snapshot, id, partial);
  assert.equal(f.checkoutStatus, "complete");
  assert.deepEqual(f.movements.map((m) => [m.kind, m.amountMinor]), [[
    "payment",
    100,
  ], ["refund", 50]]);
});
for (
  const [name, change] of Object.entries({
    currency: (s: any): unknown => s.Currency = "EUR",
    command: (s: any): unknown => s.PaymentRequestId = "foreign",
    mode: (s: any): unknown => s.PaymentType = "Reservation",
    missingAmount: (s: any): unknown => delete s.Transactions[0].Total,
    wrongAmount: (s: any): unknown => s.Transactions[0].Total = 2,
    duplicate: (s: any): unknown => s.Transactions.push(s.Transactions[0]),
    missingCompletedAt: (s: any): unknown => s.CompletedAt = null,
    unknownStatus: (s: any): unknown => s.Status = "new-vendor-status",
    foreignTransaction: (s: any): unknown =>
      s.Transactions[0].POSTransactionId = "foreign",
  })
) {
  Deno.test(`Barion rejects ${name}`, () => {
    const s = copy();
    change(s);
    assert.throws(() => barionFacts(snapshot, id, s));
  });
}
Deno.test("Barion foreign refund link is rejected", () => {
  const s = structuredClone(partial);
  s.Transactions[2].RelatedId = "a".repeat(32);
  assert.throws(() => barionFacts(snapshot, id, s));
});
Deno.test("Barion refund reversal/review or unknown movement creates a hold without retracting original payment", () => {
  for (
    const type of [
      "UnderReview",
      "ReleaseReview",
      "StornoUnSuccessfulRefundToBankCard",
      "NewChargeback",
    ]
  ) {
    const s = copy();
    s.Transactions.push({
      ...s.Transactions[0],
      TransactionId: "b".repeat(32),
      TransactionType: type,
    });
    const f = barionFacts(snapshot, id, s);
    assert.equal(f.movements.length, 1);
    assert.equal(f.disputes[0].hold, true);
  }
});
Deno.test("Barion pending refund holds admission and does not assert successful refund", () => {
  const s = structuredClone(partial);
  s.Transactions[2].Status = "Prepared";
  const f = barionFacts(snapshot, id, s);
  assert.equal(f.movements.length, 1);
  assert.equal(f.disputes.length, 1);
});
Deno.test("Barion known-ID recovery reads; lost-ID recovery never issues a new Start", async () => {
  let requests = 0;
  const p = provider();
  const connector = new BarionPaymentConnector(p);
  const claim = {
    providerId: "barion",
    disposition: "dispatch" as const,
    lease: "lease",
    snapshot,
    checkoutId: null,
    returnBaseUrl: "https://tickets.example.test/payments/barion/return",
    connectorState: {},
    source: {},
  };
  const binding = barionPaymentAdapter({
    provider: p,
    allowedOrigins: ["https://tickets.example.test"],
    verifyPlatform: async () => {},
    prepareSource: async () => ({}),
    openSource: async () => ({
      payToken: "a".repeat(64),
      returnHandle: "b".repeat(64),
    }),
    rpc: async (op) => {
      requests++;
      assert.equal(op, "defer");
      return null;
    },
  });
  const f = await connector.recoverCheckout(claim, snapshot);
  assert.equal(f.kind, "unresolved");
  await recoverPaymentClaim(claim, binding);
  assert.equal(requests, 1);
});
Deno.test("Barion callback only schedules durable authenticated read; replay does not trust body", async () => {
  const calls: string[] = [];
  const binding = barionPaymentAdapter({
    provider: provider(),
    allowedOrigins: [],
    verifyPlatform: async () => {},
    prepareSource: async () => ({}),
    openSource: async () => {
      throw Error("unused");
    },
    rpc: async (op, args) => {
      calls.push(op);
      assert.equal(args.paymentId, id);
      return null;
    },
  });
  for (let i = 0; i < 2; i++) {
    assert.equal(
      (await binding.webhook!.handle(
        new Request(`https://api.example.test/webhook?paymentId=${id}`, {
          method: "POST",
          body: '{"paid":true}',
        }),
      )).status,
      200,
    );
  }
  assert.deepEqual(calls, ["callback_schedule", "callback_schedule"]);
  assert.equal(
    (await binding.webhook!.handle(
      new Request("https://api.example.test/webhook?paymentId=foreign", {
        method: "POST",
      }),
    )).status,
    400,
  );
});
Deno.test("Barion busy durable intent prevents any second create", async () => {
  let calls = 0;
  const binding = barionPaymentAdapter({
    provider: provider(),
    allowedOrigins: [],
    verifyPlatform: async () => {},
    prepareSource: async () => ({}),
    openSource: async () => {
      throw Error("unused");
    },
    rpc: async (op) => {
      calls++;
      assert.equal(op, "claim_checkout");
      return {
        providerId: "barion",
        disposition: "busy",
        payment: { method: "barion", status: "pending" },
      };
    },
  });
  assert.deepEqual(await checkoutPayment("a".repeat(64), binding), {
    payment: { method: "barion", status: "pending" },
  });
  assert.equal(calls, 1);
});

Deno.test("Barion future unresolved recovery needs no expired source and never opens browser bearer", async () => {
  const p = provider(),
    future = {
      ...snapshot,
      createdAt: Math.floor(Date.now() / 1000),
      expiresAt: Math.floor(Date.now() / 1000) + 600,
    };
  const binding = barionPaymentAdapter({
    provider: p,
    allowedOrigins: [],
    verifyPlatform: async () => {},
    prepareSource: async () => {
      throw Error("no source");
    },
    openSource: async () => {
      throw Error("must not open source");
    },
    rpc: async (op) => {
      assert.equal(op, "defer");
      return null;
    },
  });
  const result = await recoverPaymentClaim({
    providerId: "barion",
    disposition: "dispatch",
    lease: "lease",
    snapshot: future,
    checkoutId: null,
    connectorState: {},
    source: null,
    returnBaseUrl: "https://tickets.example.test/payments/barion/return",
  }, binding);
  assert.equal(result.reconciliationPending, true);
});

Deno.test("Barion actual unpaid expiry has zero state total and no payment movement", () => {
  const f = barionFacts(
    { ...snapshot, attemptId: expired.PaymentRequestId },
    expired.PaymentId,
    expired,
  );
  assert.equal(f.checkoutStatus, "expired");
  assert.equal(f.movements.length, 0);
  assert.equal(f.disputes.length, 0);
});

Deno.test("Barion subsecond completion is rounded conservatively at the reservation boundary", () => {
  const f = barionFacts(snapshot, id, success);
  assert(f.movements[0].occurredAt * 1000 >= Date.parse(success.CompletedAt));
});

Deno.test("Barion creates checkout through common engine and commits canonical sandbox identity", async () => {
  const now = Math.floor(Date.now() / 1000),
    future = { ...snapshot, createdAt: now, expiresAt: now + 1860 };
  const operations: string[] = [];
  let starts = 0;
  const p = new BarionSandboxProvider({
    accountId: future.accountId,
    posKey: "12345678123442348234123456789abc",
    payee: "merchant@example.test",
    callbackUrl: "https://callback.example.test/hint",
    allowedReturnOrigins: ["https://tickets.example.test"],
    fetch: async (_url, init) => {
      starts++;
      const request = JSON.parse(String(init?.body));
      assert.equal(request.PaymentRequestId, future.attemptId);
      assert.equal(
        new URL(request.RedirectUrl).searchParams.get("return_handle"),
        "b".repeat(64),
      );
      return Response.json({
        PaymentId: id,
        PaymentRequestId: future.attemptId,
        Status: "Prepared",
        GatewayUrl: `https://secure.test.barion.com/pay?id=${id}`,
      });
    },
  });
  const binding = barionPaymentAdapter({
    provider: p,
    allowedOrigins: ["https://tickets.example.test"],
    verifyPlatform: async () => {},
    prepareSource: async () => ({}),
    openSource: async () => ({
      payToken: "a".repeat(64),
      returnHandle: "b".repeat(64),
    }),
    rpc: async (op, args) => {
      operations.push(op);
      if (op === "claim_checkout") {
        return {
          providerId: "barion",
          disposition: "dispatch",
          lease: "lease",
          snapshot: future,
          checkoutId: null,
          returnBaseUrl: "https://tickets.example.test/payments/barion/return",
          connectorState: {},
          source: {},
        };
      }
      assert.equal(op, "commit_checkout");
      const checkout = args.checkout as { id: string; url: string };
      assert.equal(checkout.id, id);
      assert.equal(checkout.url, `https://secure.test.barion.com/Pay?Id=${id}`);
      return { committed: true, payment: { method: "barion", status: "open" } };
    },
  });
  assert.equal(
    (await checkoutPayment("a".repeat(64), binding)).checkoutUrl,
    `https://secure.test.barion.com/Pay?Id=${id}`,
  );
  assert.equal(starts, 1);
  assert.deepEqual(operations, ["claim_checkout", "commit_checkout"]);
});
