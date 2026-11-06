import {
  existsSync,
  mkdirSync,
  readdirSync,
  readFileSync,
  writeFileSync,
} from "node:fs";
import { join, resolve } from "node:path";

/** Scope dispatch guards to explicitly named independent test cases, never an
 * automatic replacement of an uncertain customer/payment command.
 */
export function reserveSandboxCase(
  { root, caseId, attemptId, receiptPath, previousActive, independentOf },
) {
  if (!/^[a-z][a-z0-9-]{0,63}$/.test(caseId ?? "")) {
    throw new Error("explicit_sandbox_case_required");
  }
  const cases = join(root, "cases");
  mkdirSync(cases, { recursive: true, mode: 0o700 });
  let prior;
  if (previousActive && existsSync(previousActive)) {
    const active = JSON.parse(readFileSync(previousActive, "utf8"));
    if (!resolve(active.receiptPath).startsWith(resolve(root) + "/")) {
      throw new Error("sandbox_receipt_scope_invalid");
    }
    prior = JSON.parse(readFileSync(active.receiptPath, "utf8"));
  }
  if (prior && ["dispatched", "uncertain"].includes(prior.disposition)) {
    if (
      caseId === prior.caseId || !independentOf ||
      independentOf !== prior.attemptId
    ) {
      throw new Error("previous_create_unresolved_no_replay");
    }
  }
  const entry = {
    caseId,
    attemptId,
    receiptPath,
    ...(prior && ["dispatched", "uncertain"].includes(prior.disposition)
      ? {
        independentOf: prior.attemptId,
        previousOutcomeRemainsUnresolved: true,
      }
      : {}),
  };
  try {
    writeFileSync(join(cases, caseId + ".json"), JSON.stringify(entry) + "\n", {
      flag: "wx",
      mode: 0o600,
    });
  } catch (error) {
    if (error.code === "EEXIST") {
      throw new Error("sandbox_case_already_reserved_no_replay");
    }
    throw error;
  }
  return entry;
}

/** Bootstrap can resume only before any remote dispatch. Reuse the same case
 * and command; a dispatched/uncertain receipt is never accepted here.
 */
export function preparedSandboxCase({ root, attemptId, caseId }) {
  if (
    !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
      attemptId ?? "",
    )
  ) throw new Error("invalid_prepared_case");
  const receiptPath = join(root, attemptId, "receipt.json");
  const receipt = JSON.parse(readFileSync(receiptPath, "utf8"));
  if (
    receipt.attemptId !== attemptId || receipt.caseId !== caseId ||
    receipt.disposition !== "prepared" || receipt.dispatchedAt ||
    receipt.amountMinor !== 100 || receipt.currency !== "CZK"
  ) throw new Error("prepared_case_was_dispatched_no_replay");
  return { receiptPath, receipt };
}

/** A new refund command cannot conceal an earlier lost response on this payment. */
export function reserveSandboxRefund(directory, command, intent) {
  for (
    const name of readdirSync(directory).filter((n) =>
      /^refund-.*\.json$/.test(n)
    )
  ) {
    const previous = JSON.parse(readFileSync(join(directory, name), "utf8"));
    if (["dispatched", "uncertain"].includes(previous.state)) {
      throw new Error("previous_refund_unresolved_no_replay");
    }
  }
  const path = join(directory, `refund-${command}.json`);
  writeFileSync(path, JSON.stringify(intent) + "\n", {
    flag: "wx",
    mode: 0o600,
  });
  return path;
}
