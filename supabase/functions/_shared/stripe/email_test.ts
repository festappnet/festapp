import { strict as assert } from "node:assert";
import { stripeConfirmationBalance } from "./email.ts";
import { safeClickTracking } from "../emailTracking.ts";
const secrets = { payToken: "a".repeat(64), returnHandle: "b".repeat(64) };
Deno.test("A08/A15 card confirmation has a private fragment link without bank instructions or click tracking", () => {
  const html = stripeConfirmationBalance(
    {
      payBaseUrl: "https://tickets.example/stripe/pay",
      payment: { method: "stripe", status: "open" },
    },
    secrets,
    "cs",
    "123,45 CZK",
    "12:00",
    ["https://tickets.example"],
  );
  assert.match(html, /#pay=a{64}/);
  assert(!html.includes("return_handle"));
  assert(!html.includes("variabilní"));
  assert.equal(safeClickTracking(html, ["https://tickets.example"]), false);
  assert.throws(() =>
    stripeConfirmationBalance(
      {
        payBaseUrl: "https://foreign.example/stripe/pay",
        payment: { method: "stripe", status: "open" },
      },
      secrets,
      "cs",
      "1",
      "12:00",
      ["https://tickets.example"],
    )
  );
});
Deno.test("A16/A17 delayed confirmation renders current refunds and never a new payment invitation", () => {
  for (
    const status of [
      "paid",
      "refunded",
      "partially_refunded",
      "disputed",
      "expired",
      "action_required",
    ]
  ) {
    const html = stripeConfirmationBalance(
      { payment: { method: "stripe", status } },
      undefined,
      "en",
      "123.45 CZK",
      "12:00",
      [],
    );
    assert(!html.includes("href="));
    assert(!html.includes(secrets.payToken));
  }
});
