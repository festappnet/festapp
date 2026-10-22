import { strict as assert } from "node:assert";
import { disputeFact, paymentFact, refundFact } from "./facts.ts";
import { type CheckoutSnapshot, StripeBoundaryError } from "./provider.ts";
const snapshot: CheckoutSnapshot = {
  attemptId: "attempt_fixture",
  accountId: "acct_fixture",
  livemode: false,
  amountMinor: 123450,
  currency: "CZK",
  orderReference: "Order fixture",
  expiresAt: 1790001900,
  createdAt: 1790000000,
  idempotencyKey: "fixture:attempt_fixture",
  returnUrl: `https://example.com/return?return_handle=${"a".repeat(64)}`,
};
const intent = {
  id: "pi_fixture",
  object: "payment_intent",
  livemode: false,
  status: "succeeded",
  amount: 123450,
  amount_received: 123450,
  currency: "czk",
  metadata: { festapp_attempt: snapshot.attemptId },
  latest_charge: { id: "ch_fixture", created: 1790000015 },
};
const session = {
  object: "checkout.session",
  livemode: false,
  client_reference_id: snapshot.attemptId,
  amount_total: 123450,
  currency: "czk",
  mode: "payment",
  payment_status: "paid",
  payment_intent: intent,
};
Deno.test("A12 paid fact requires expanded succeeded PaymentIntent and immutable gross amount", () => {
  assert.equal(paymentFact(snapshot, session)?.amountMinor, 123450);
  assert.equal(
    paymentFact(snapshot, { ...session, payment_status: "unpaid" }),
    null,
  );
  for (
    const patch of [
      { status: "processing" },
      { amount_received: 1 },
      { livemode: true },
      { metadata: {} },
      { transfer_data: { destination: "acct_other" } },
      { application_fee_amount: 1 },
    ]
  ) {
    assert.throws(
      () =>
        paymentFact(snapshot, {
          ...session,
          payment_intent: { ...intent, ...patch },
        }),
      StripeBoundaryError,
    );
  }
  assert.throws(
    () => paymentFact(snapshot, { ...session, payment_intent: "pi_fixture" }),
    StripeBoundaryError,
  );
});
Deno.test("A23 original charge time, never webhook time or PaymentIntent creation time", () => {
  assert.equal(paymentFact(snapshot, session)?.occurredAt, 1790000015);
  assert.throws(
    () =>
      paymentFact(snapshot, {
        ...session,
        payment_intent: { ...intent, latest_charge: "ch_fixture" },
      }),
    StripeBoundaryError,
  );
});
const refund = {
  id: "re_fixture",
  object: "refund",
  payment_intent: "pi_fixture",
  amount: 23450,
  currency: "czk",
  created: 1790086400,
  status: "succeeded",
};
Deno.test("A16/A17 only successful immutable refunds count; pending and failed are not finance", () => {
  assert.equal(refundFact(snapshot, "pi_fixture", refund)?.amountMinor, 23450);
  assert.equal(
    refundFact(snapshot, "pi_fixture", { ...refund, status: "pending" }),
    null,
  );
  assert.equal(
    refundFact(snapshot, "pi_fixture", { ...refund, status: "failed" }),
    null,
  );
  assert.throws(
    () => refundFact(snapshot, "pi_other", refund),
    StripeBoundaryError,
  );
  assert.throws(
    () => refundFact(snapshot, "pi_fixture", { ...refund, amount: 123451 }),
    StripeBoundaryError,
  );
});
Deno.test("A12 duplicate refund snapshots retain their economic identity regardless of event IDs", () => {
  assert.deepEqual(
    refundFact(snapshot, "pi_fixture", refund),
    refundFact(snapshot, "pi_fixture", {
      ...refund,
      metadata: { delivery: "different-event" },
    }),
  );
  assert.equal(
    refundFact(snapshot, "pi_fixture", { ...refund, amount: 123450 })?.kind,
    "refund",
  );
});
Deno.test("A18 dispute is an admission hold, not another refund; won and warning do not hold", () => {
  const d = {
    id: "dp_fixture",
    object: "dispute",
    payment_intent: "pi_fixture",
    amount: 123450,
    currency: "czk",
    livemode: false,
    status: "needs_response",
  };
  assert.equal(disputeFact(snapshot, "pi_fixture", d).hold, true);
  assert.equal(
    disputeFact(snapshot, "pi_fixture", { ...d, id: "du_fixture" }).currency,
    "CZK",
  );
  assert.equal(
    disputeFact(snapshot, "pi_fixture", { ...d, status: "won" }).hold,
    false,
  );
  assert.equal(
    disputeFact(snapshot, "pi_fixture", { ...d, status: "warning_closed" })
      .hold,
    false,
  );
  assert.equal(
    disputeFact(snapshot, "pi_fixture", { ...d, status: "lost" }).hold,
    true,
  );
  assert.throws(
    () => disputeFact(snapshot, "pi_foreign", d),
    StripeBoundaryError,
  );
});
