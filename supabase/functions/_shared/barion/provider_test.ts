import { strict as assert } from "node:assert";
import {
  BarionRequestError,
  type BarionSandboxConfiguration,
  BarionSandboxProvider,
} from "./provider.ts";
import type { CheckoutSnapshot } from "../payments/contracts.ts";
const attempt = "12345678-1234-4234-8234-123456789abc",
  payment = "23456789123442348234123456789abc";
const configuration: BarionSandboxConfiguration = {
  accountId: "shop-fixture",
  posKey: "34567890-1234-4234-8234-123456789abc",
  payee: "merchant@example.test",
  callbackUrl: "https://callback.example.test/callback",
  allowedReturnOrigins: ["https://tickets.example.test"],
};
function snapshot(): CheckoutSnapshot {
  const now = Math.floor(Date.now() / 1000);
  return {
    attemptId: attempt,
    accountId: "shop-fixture",
    livemode: false,
    amountMinor: 12345,
    currency: "CZK",
    orderReference: "Sandbox fixture",
    createdAt: now,
    expiresAt: now + 1860,
    idempotencyKey: attempt,
    returnUrl: "https://tickets.example.test/payments/return",
    locale: "cs",
  };
}
const started = () => ({
  PaymentId: payment,
  PaymentRequestId: attempt,
  Status: "Prepared",
  GatewayUrl: `https://secure.test.barion.com/Pay?Id=${payment}`,
  Errors: [],
});
const state = () => ({
  PaymentId: payment,
  PaymentRequestId: attempt,
  PaymentType: "Immediate",
  Status: "Succeeded",
  Currency: "CZK",
  Transactions: [],
  Errors: [],
});
Deno.test("Barion sandbox Start binds one payee, immutable command, amount and callback", async () => {
  const requests: RequestInit[] = [];
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async (url, init) => {
      assert.equal(String(url), "https://api.test.barion.com/v2/Payment/Start");
      requests.push(init!);
      return Response.json(started());
    },
  });
  const checkout = await provider.createPayment(snapshot());
  assert.equal(checkout.id, payment);
  const body = JSON.parse(String(requests[0].body));
  assert.equal(
    new Headers(requests[0].headers).get("Idempotency-Key"),
    attempt,
  );
  assert.equal(body.PaymentRequestId, attempt);
  assert.equal(body.Transactions.length, 1);
  assert.equal(body.Transactions[0].Payee, configuration.payee);
  assert.equal(body.Transactions[0].Total, 123.45);
  assert.equal(body.Transactions[0].Items[0].ItemTotal, 123.45);
  assert.equal(body.CallbackUrl, configuration.callbackUrl);
  assert.equal(requests[0].redirect, "error");
  assert(requests[0].signal);
});
Deno.test("Barion sandbox refuses live, foreign account and unsupported precision before I/O", async () => {
  let requests = 0;
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async () => {
      requests++;
      return Response.json(started());
    },
  });
  for (
    const changed of [
      { livemode: true },
      { accountId: "foreign" },
      { currency: "HUF" },
      { amountMinor: 1.5 },
      { amountMinor: 1_000_000_001 },
    ]
  ) {
    await assert.rejects(
      () => provider.createPayment({ ...snapshot(), ...changed }),
      /barion_snapshot_invalid/,
    );
  }
  assert.equal(requests, 0);
});
Deno.test("Barion authenticated state requires the saved payment, command, type and currency", async () => {
  let response: Record<string, unknown> = state();
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async (url, init) => {
      assert.equal(
        String(url),
        `https://api.test.barion.com/v4/payment/${payment}/paymentstate`,
      );
      assert.equal(
        new Headers(init?.headers).get("x-pos-key"),
        configuration.posKey,
      );
      return Response.json(response);
    },
  });
  assert.equal(
    (await provider.paymentState(snapshot(), payment)).Status,
    "Succeeded",
  );
  for (
    const changed of [
      { PaymentId: attempt },
      { PaymentRequestId: "foreign" },
      { PaymentType: "Reservation" },
      { Currency: "EUR" },
      { Transactions: null },
    ]
  ) {
    response = { ...state(), ...changed };
    await assert.rejects(
      () => provider.paymentState(snapshot(), payment),
      /barion_response_invalid|barion_remote_rejected/,
    );
  }
});
Deno.test("Barion gateway redirects reject foreign hosts, identities and injected parameters", async () => {
  const provider = new BarionSandboxProvider(configuration);
  for (
    const value of [
      `https://secure.barion.com/Pay?Id=${payment}`,
      `https://evil.example/Pay?Id=${payment}`,
      `https://secure.test.barion.com/Pay?Id=${payment}&return=https://evil.example`,
      `https://user@secure.test.barion.com/Pay?Id=${payment}`,
    ]
  ) {
    assert.throws(
      () => provider.validateCheckoutUrl(value),
      /barion_response_invalid|barion_remote_rejected/,
    );
  }
});
Deno.test("Barion uncertain create never performs an internal retry or leaks remote errors", async () => {
  let requests = 0;
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async () => {
      requests++;
      throw new Error("private key or remote body");
    },
  });
  await assert.rejects(
    () => provider.createPayment(snapshot()),
    (error) =>
      error instanceof Error && error.message === "barion_remote_uncertain",
  );
  assert.equal(requests, 1);
});
Deno.test("Barion error envelopes and malformed bodies cannot masquerade as a checkout", async () => {
  for (
    const result of [
      {
        ...started(),
        Errors: [{ ErrorCode: "InvalidPOS", Description: "private details" }],
      },
      null,
      {},
      {
        ...started(),
        GatewayUrl: `https://secure.test.barion.com/Pay?Id=${attempt}`,
      },
    ]
  ) {
    const provider = new BarionSandboxProvider({
      ...configuration,
      fetch: async () => Response.json(result),
    });
    await assert.rejects(
      () => provider.createPayment(snapshot()),
      /barion_response_invalid|barion_remote_rejected/,
    );
  }
});

Deno.test("Barion draft rejection retains safe HTTP/code diagnostics without provider descriptions", async () => {
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async () =>
      Response.json({
        Errors: [{
          ErrorCode: "ShopIsInDraftState",
          Description: "private contact and credential details",
        }],
      }, { status: 401 }),
  });
  await assert.rejects(
    () => provider.createPayment(snapshot()),
    (error) =>
      error instanceof BarionRequestError && error.httpStatus === 401 &&
      error.providerCode === "ShopIsInDraftState" &&
      !JSON.stringify(error).includes("private contact"),
  );
});

Deno.test("Barion checkout validates GUID identity independently of URL path/query casing", async () => {
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async () =>
      Response.json({
        ...started(),
        GatewayUrl: `https://secure.test.barion.com/pay?id=${payment}`,
      }),
  });
  assert.equal((await provider.createPayment(snapshot())).id, payment);
});

Deno.test("sandbox refund snapshots transaction, amount and command with no automatic retry", async () => {
  const command = "45678901-1234-4234-8234-123456789abc";
  let calls = 0;
  const provider = new BarionSandboxProvider({
    ...configuration,
    fetch: async (url, init) => {
      calls++;
      assert.equal(
        String(url),
        "https://api.test.barion.com/v2/Payment/Refund",
      );
      assert.equal(new Headers(init?.headers).get("Idempotency-Key"), command);
      const body = JSON.parse(String(init?.body));
      assert.equal(body.PaymentId, payment);
      assert.deepEqual(body.TransactionsToRefund, [{
        TransactionId: payment,
        POSTransactionId: command,
        AmountToRefund: 0.5,
      }]);
      throw Error("transport lost");
    },
  });
  await assert.rejects(
    () => provider.refund(snapshot(), payment, payment, 50, command),
    /barion_remote_uncertain/,
  );
  assert.equal(calls, 1);
  await assert.rejects(
    () =>
      provider.refund(
        { ...snapshot(), livemode: true },
        payment,
        payment,
        50,
        command,
      ),
    /barion_snapshot_invalid/,
  );
  assert.equal(calls, 1);
});
