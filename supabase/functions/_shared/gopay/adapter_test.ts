import { deepStrictEqual, rejects, strictEqual } from "node:assert";
import type { CheckoutSnapshot } from "../payments/contracts.ts";
import { GoPayPaymentConnector, goPayWebhook } from "./adapter.ts";
import { GoPaySandboxProvider } from "./provider.ts";

const origin = "https://prodej-demo.vstupenky.online";
const callbackToken = "c".repeat(64);
const paymentId = "3123456789";
const checkoutUrl = "https://gw.sandbox.gopay.com/gw/v3/Card123";
const snapshot: CheckoutSnapshot = {
  attemptId: "620de428-b130-4d71-9aeb-ff235ffa63da",
  accountId: "8123456789",
  livemode: false,
  amountMinor: 50000,
  currency: "CZK",
  orderReference: "Order 10",
  expiresAt: 4000,
  createdAt: 1000,
  idempotencyKey: "620de428-b130-4d71-9aeb-ff235ffa63da",
  returnUrl: `${origin}/payments/gopay/return?return_handle=${"f".repeat(64)}`,
};

function fixture(state = "CREATED", amount = 50000) {
  const requests: Request[] = [];
  const provider = new GoPaySandboxProvider({
    goId: snapshot.accountId,
    clientId: "test-client",
    clientSecret: "stub-credential",
    storefrontOrigin: origin,
    notificationUrl:
      `https://api.example.test/functions/v1/payment-webhook?provider=gopay&hook=${callbackToken}`,
  }, (resource, options) => {
    const req = new Request(resource, options);
    requests.push(req);
    const path = new URL(req.url).pathname;
    return Promise.resolve(
      path === "/api/oauth2/token"
        ? Response.json({ access_token: "stub-token", token_type: "bearer" })
        : Response.json({
          id: Number(paymentId),
          order_number: snapshot.attemptId.replaceAll("-", ""),
          target: { type: "ACCOUNT", goid: Number(snapshot.accountId) },
          amount,
          currency: "CZK",
          gw_url: checkoutUrl,
          state,
        }),
    );
  });
  return {
    connector: new GoPayPaymentConnector(provider, () => 1234),
    requests,
  };
}

Deno.test("GoPay creates one CZK sandbox card checkout for the bound organizer", async () => {
  const { connector, requests } = fixture();
  const checkout = await connector.createOrRecoverCheckout(snapshot);
  deepStrictEqual(checkout, {
    id: paymentId,
    url: checkoutUrl,
    status: "open",
    expiresAt: 4000,
  });
  const [token, create] = requests;
  strictEqual(token.url, "https://gw.sandbox.gopay.com/api/oauth2/token");
  strictEqual(
    new URLSearchParams(await token.text()).get("scope"),
    "payment-create",
  );
  strictEqual(create.headers.get("authorization"), "Bearer stub-token");
  const body = await create.json();
  deepStrictEqual(body.target, { type: "ACCOUNT", goid: 8123456789 });
  deepStrictEqual(body.payer.allowed_payment_instruments, ["PAYMENT_CARD"]);
  strictEqual(body.callback.return_url, snapshot.returnUrl);
  await rejects(() =>
    connector.createOrRecoverCheckout({ ...snapshot, livemode: true })
  );
  await rejects(() =>
    connector.createOrRecoverCheckout({
      ...snapshot,
      returnUrl: "https://other.vstupenky.online/payments/gopay/return",
    })
  );
  strictEqual(requests.length, 2);
});

Deno.test("GoPay records bound PAID once and uses a stable first-observed time", async () => {
  const { connector, requests } = fixture("PAID");
  const first = await connector.observePayment(snapshot, paymentId, {});
  const repeat = await connector.observePayment(snapshot, paymentId, {
    paidObservedAt: "1234",
  });
  deepStrictEqual(first, repeat);
  deepStrictEqual(first.movements, [{
    providerId: paymentId,
    kind: "payment",
    amountMinor: 50000,
    currency: "CZK",
    occurredAt: 1234,
  }]);
  strictEqual(
    new URLSearchParams(await requests[0].text()).get("scope"),
    "payment-all",
  );
  await rejects(
    () =>
      fixture("PAID", 49000).connector.observePayment(snapshot, paymentId, {}),
    /gopay_payment_mismatch/,
  );
});

Deno.test("GoPay pending, expiration and refund observations have distinct effects", async () => {
  const { connector } = fixture("PAYMENT_METHOD_CHOSEN");
  strictEqual((await connector.checkout(snapshot, paymentId)).url, null);
  deepStrictEqual(
    (await connector.observePayment(snapshot, paymentId, {})).movements,
    [],
  );
  for (const state of ["CANCELED", "TIMEOUTED"]) {
    const observation = await fixture(state).connector.observePayment(
      snapshot,
      paymentId,
      {},
    );
    strictEqual(observation.checkoutStatus, "expired");
    deepStrictEqual(observation.movements, []);
  }
  const refund = await fixture("PARTIALLY_REFUNDED").connector.observePayment(
    snapshot,
    paymentId,
    {},
  );
  strictEqual(refund.disputes[0].hold, true);
  strictEqual(refund.movements.length, 1);
});

Deno.test("GoPay GET notification schedules the ID and sends no payment facts", async () => {
  const events: unknown[] = [];
  const rpc = (operation: string, args: Record<string, unknown>) => {
    events.push({ operation, args });
    return Promise.resolve(null);
  };
  const url =
    `https://api.example.test/payment-webhook?provider=gopay&hook=${callbackToken}&id=${paymentId}`;
  strictEqual(
    (await goPayWebhook(new Request(url), rpc, callbackToken)).status,
    200,
  );
  strictEqual(
    (await goPayWebhook(new Request(`${url}&id=123`), rpc, callbackToken))
      .status,
    400,
  );
  strictEqual(
    (await goPayWebhook(
      new Request(url, { method: "POST" }),
      rpc,
      callbackToken,
    )).status,
    405,
  );
  strictEqual(
    (await goPayWebhook(new Request(url), rpc, "d".repeat(64))).status,
    403,
  );
  deepStrictEqual(events, [{
    operation: "callback_schedule",
    args: { paymentId },
  }]);
});
