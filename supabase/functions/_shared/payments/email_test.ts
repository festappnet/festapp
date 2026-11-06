import { strict as assert } from "node:assert";
import { paymentConfirmationBalance } from "./email.ts";
Deno.test("another provider renders its own private payment link and escaped identity", () => {
  const policy = {
    providerId: "other_gateway",
    providerName: "Other <gateway>",
    payPath: "/payments/other_gateway/pay",
    allowedOrigins: ["https://tickets.example"],
  };
  const source = {
    payment: { method: policy.providerId, status: "open" },
    payBaseUrl: "https://tickets.example/payments/other_gateway/pay",
  };
  const html = paymentConfirmationBalance(
    source,
    { payToken: "a".repeat(64), returnHandle: "b".repeat(64) },
    "cs",
    "123,45 Kč",
    "12:00",
    policy,
  );
  assert(html.includes("Other &lt;gateway&gt;"));
  assert(html.includes("#pay=" + "a".repeat(64)));
  assert(!html.includes("Stripe"));
  assert.throws(() =>
    paymentConfirmationBalance(
      {
        ...source,
        payBaseUrl: "https://evil.example/payments/other_gateway/pay",
      },
      { payToken: "a".repeat(64), returnHandle: "b".repeat(64) },
      "cs",
      "123",
      "12:00",
      policy,
    )
  );
});
