/** Explicit sandbox-only probe of the actual provider boundary; not Festapp E2E.
 * Secrets and the durable probe receipt must remain outside the repository.
 * Does not capture/confirm/refund payments or change account configuration.
 */
import {
  type CheckoutSnapshot,
  StripeProvider,
} from "../../supabase/functions/_shared/stripe/provider.ts";
import {
  paymentFact,
  refundFact,
} from "../../supabase/functions/_shared/stripe/facts.ts";
const [mode = "inspect", configPath, receiptPath] = Deno.args;
if (
  !["inspect", "checkout", "read"].includes(mode) || !configPath || !receiptPath
) {
  throw new Error(
    "Usage: sandbox-probe.ts inspect|checkout|read <private-config.env> <private-receipt.json>",
  );
}
const root = await Deno.realPath(new URL("../..", import.meta.url));
const configReal = await Deno.realPath(configPath);
const receiptParent = await Deno.realPath(
  receiptPath.substring(0, receiptPath.lastIndexOf("/")),
);
if (
  [configReal, receiptParent].some((p) =>
    p === root || p.startsWith(root + "/")
  )
) throw new Error("Probe private files must be outside the repository");
const config = Object.fromEntries(
  (await Deno.readTextFile(configReal)).trim().split("\n").map((line) => {
    const index = line.indexOf("=");
    return [line.slice(0, index), line.slice(index + 1)];
  }),
);
if (
  !/^sk_test_[A-Za-z0-9]+$/.test(config.STRIPE_SECRET_KEY ?? "") ||
  !/^acct_[A-Za-z0-9]+$/.test(config.STRIPE_TEST_ORGANIZER ?? "") ||
  config.STRIPE_TEST_ORGANIZER === config.STRIPE_SANDBOX_ACCOUNT
) throw new Error("Distinct sandbox organizer and platform are required");
const provider = new StripeProvider({
  secretKey: config.STRIPE_SECRET_KEY,
  livemode: false,
  apiVersion: "2025-06-30.basil",
  allowedReturnOrigins: ["http://127.0.0.1:61171"],
});
if (mode === "inspect") {
  console.log(
    JSON.stringify(await provider.account(config.STRIPE_TEST_ORGANIZER)),
  );
  Deno.exit();
}
let receipt: {
  snapshot: CheckoutSnapshot;
  sessionId?: string;
  url?: string;
  expiresAt?: number;
};
try {
  receipt = JSON.parse(await Deno.readTextFile(receiptPath));
} catch (e) {
  if (!(e instanceof Deno.errors.NotFound)) throw e;
  if (mode !== "checkout") {
    throw new Error("A durable sandbox receipt is required");
  }
  const now = Math.floor(Date.now() / 1000),
    attemptId = "festapp_probe_" + crypto.randomUUID();
  receipt = {
    snapshot: {
      attemptId,
      accountId: config.STRIPE_TEST_ORGANIZER,
      livemode: false,
      amountMinor: 12345,
      currency: "CZK",
      orderReference: "Festapp sandbox probe (no real ticket)",
      createdAt: now,
      expiresAt: now + 1800,
      idempotencyKey: attemptId,
      returnUrl: "http://127.0.0.1:61171/return?return_handle=" +
        crypto.randomUUID().replaceAll("-", "") +
        crypto.randomUUID().replaceAll("-", ""),
    },
  };
  await Deno.writeTextFile(receiptPath, JSON.stringify(receipt), {
    mode: 0o600,
    createNew: true,
  });
}
if (
  receipt.snapshot.accountId !== config.STRIPE_TEST_ORGANIZER ||
  receipt.snapshot.livemode !== false
) throw new Error("Receipt account/environment mismatch");
if (mode === "checkout" && !receipt.sessionId) {
  const result = await provider.createCheckout(receipt.snapshot);
  receipt = { ...receipt, ...result };
  await Deno.writeTextFile(receiptPath, JSON.stringify(receipt), {
    mode: 0o600,
  });
  console.log(
    "Sandbox Checkout created; private receipt saved. No payment confirmed.",
  );
} else {
  if (!receipt.sessionId) {
    throw new Error(
      "Preparation is uncertain; retain the same receipt and key",
    );
  }
  const session = await provider.session(receipt.snapshot, receipt.sessionId);
  const fact = paymentFact(receipt.snapshot, session);
  const refunds = fact
    ? await provider.refunds(receipt.snapshot, fact.providerId)
    : null;
  console.log(JSON.stringify({
    sessionId: session.id,
    account: receipt.snapshot.accountId,
    livemode: session.livemode,
    paymentStatus: session.payment_status,
    status: session.status,
    amount: session.amount_total,
    currency: session.currency,
    verifiedPayment: fact,
    refunds: refunds?.data.map((r) =>
      refundFact(receipt.snapshot, fact!.providerId, r)
    ).filter(Boolean),
    refundCursor: refunds?.nextCursor,
  }));
}
