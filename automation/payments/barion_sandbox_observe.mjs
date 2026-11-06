import { reserveSandboxRefund } from "./sandbox_intent.mjs";
// Run with Deno permissions matching barion_sandbox_probe.mjs (security only).
// Existing private receipt supplies identity; no secret values reach stdout.
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { execFileSync } from "node:child_process";
import { BarionSandboxProvider } from "../../supabase/functions/_shared/barion/provider.ts";
import { barionFacts } from "../../supabase/functions/_shared/barion/facts.ts";
const arg = (name) =>
  process.argv.find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
const meta = JSON.parse(
  readFileSync("/tmp/festapp-barion-sandbox-active.json", "utf8"),
);
if (arg("attempt")) {
  if (!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(arg("attempt"))) {
    throw Error("invalid_attempt");
  }
  meta.receiptPath = join(
    dirname(dirname(meta.receiptPath)),
    arg("attempt"),
    "receipt.json",
  );
}
const receipt = JSON.parse(readFileSync(meta.receiptPath, "utf8"));
if (
  receipt.disposition !== "remote_created" ||
  receipt.snapshot?.livemode !== false
) throw Error("known_sandbox_payment_required");
const secret = (service) =>
  execFileSync("security", [
    "find-generic-password",
    "-s",
    service,
    "-a",
    "festapp-sandbox",
    "-w",
  ], { stdio: ["ignore", "pipe", "pipe"] }).toString().trim();
const provider = new BarionSandboxProvider({
  accountId: receipt.snapshot.accountId,
  posKey: secret("festapp-barion-sandbox-poskey"),
  payee: secret("festapp-barion-sandbox-payee"),
  callbackUrl: "https://example.invalid/unused",
  allowedReturnOrigins: [],
});
const state = await provider.paymentState(receipt.snapshot, receipt.paymentId);
const facts = barionFacts(receipt.snapshot, receipt.paymentId, state);

const amount = arg("refund-minor");
if (amount !== undefined) {
  if (!process.argv.includes("--dispatch-sandbox-refund")) {
    throw Error("explicit_sandbox_refund_required");
  }
  const command = arg("command");
  if (!/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/.test(command ?? "")) {
    throw Error("refund_command_required");
  }
  const original = facts.movements.find((m) => m.kind === "payment");
  const refunded = facts.movements.filter((m) => m.kind === "refund").reduce(
    (sum, m) => sum + m.amountMinor,
    0,
  );
  if (
    !original || !/^\d+$/.test(amount) || Number(amount) <= 0 ||
    Number(amount) + refunded > original.amountMinor
  ) throw Error("refund_amount_invalid");
  const intent = {
    command,
    amountMinor: Number(amount),
    paymentId: receipt.paymentId,
    state: "dispatched",
    createdAt: new Date().toISOString(),
  };
  const path = reserveSandboxRefund(dirname(meta.receiptPath), command, intent);
  try {
    await provider.refund(
      receipt.snapshot,
      receipt.paymentId,
      original.providerId,
      Number(amount),
      command,
    );
    intent.state = "accepted";
  } catch (error) {
    intent.state = "uncertain";
    intent.error = error.code;
    intent.httpStatus = error.httpStatus;
    intent.providerCode = error.providerCode;
  }
  writeFileSync(path, JSON.stringify(intent) + "\n", { mode: 0o600 });
  console.log(
    JSON.stringify({
      operation: "refund",
      state: intent.state,
      httpStatus: intent.httpStatus,
      providerCode: intent.providerCode,
    }),
  );
  if (intent.state !== "accepted") process.exitCode = 1;
} else {
  const redacted = {
    PaymentId: state.PaymentId,
    PaymentRequestId: state.PaymentRequestId,
    Status: state.Status,
    Currency: state.Currency,
    Total: state.Total,
    PaymentType: state.PaymentType,
    CompletedAt: state.CompletedAt,
    Transactions: state.Transactions.map((t) =>
      Object.fromEntries(
        [
          "TransactionId",
          "POSTransactionId",
          "TransactionTime",
          "Total",
          "Currency",
          "Status",
          "TransactionType",
          "RelatedId",
        ].map((k) => [k, t[k] ?? null]),
      )
    ),
  };
  const path = join(dirname(meta.receiptPath), `state-${Date.now()}.json`);
  writeFileSync(
    path,
    JSON.stringify({ state: redacted, facts }, null, 2) + "\n",
    { flag: "wx", mode: 0o600 },
  );
  console.log(JSON.stringify({
    status: state.Status,
    receivedMinor: facts.movements.filter((m) => m.kind === "payment").reduce(
      (s, m) => s + m.amountMinor,
      0,
    ),
    refundedMinor: facts.movements.filter((m) => m.kind === "refund").reduce(
      (s, m) => s + m.amountMinor,
      0,
    ),
    held: facts.disputes.length > 0,
    receiptPath: path,
  }));
}
