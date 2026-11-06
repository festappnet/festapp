import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { reserveSandboxCase, reserveSandboxRefund } from "./sandbox_intent.mjs";
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), "festapp-sandbox-intent-"));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const receiptPath = join(root, "old.json"),
    previousActive = join(root, "active.json");
  writeFileSync(
    receiptPath,
    JSON.stringify({
      attemptId: "old-command",
      caseId: "onboarding-probe",
      disposition: "uncertain",
    }),
  );
  writeFileSync(previousActive, JSON.stringify({ receiptPath }));
  return { root, receiptPath, previousActive };
}
test("uncertain case cannot silently acquire a different command", (t) => {
  const f = fixture(t);
  assert.throws(
    () =>
      reserveSandboxCase({
        ...f,
        caseId: "onboarding-probe",
        attemptId: "new",
      }),
    /no_replay/,
  );
  assert.throws(
    () =>
      reserveSandboxCase({ ...f, caseId: "approved-smoke", attemptId: "new" }),
    /no_replay/,
  );
  assert.throws(
    () =>
      reserveSandboxCase({
        ...f,
        caseId: "approved-smoke",
        attemptId: "new",
        independentOf: "foreign",
      }),
    /no_replay/,
  );
});
test("a deliberate independent test preserves the earlier uncertainty and is itself one-shot", (t) => {
  const f = fixture(t), before = readFileSync(f.receiptPath, "utf8");
  const entry = reserveSandboxCase({
    ...f,
    caseId: "approved-smoke",
    attemptId: "new",
    independentOf: "old-command",
  });
  assert.equal(entry.previousOutcomeRemainsUnresolved, true);
  assert.equal(entry.independentOf, "old-command");
  assert.equal(readFileSync(f.receiptPath, "utf8"), before);
  assert.throws(
    () =>
      reserveSandboxCase({
        ...f,
        caseId: "approved-smoke",
        attemptId: "another",
        independentOf: "old-command",
      }),
    /already_reserved_no_replay/,
  );
});

test("only an undispatched bootstrap can resume its original command", async (t) => {
  const { preparedSandboxCase } = await import("./sandbox_intent.mjs");
  const f = fixture(t), attemptId = "12345678-1234-4234-8234-123456789abc";
  const directory = join(f.root, attemptId);
  mkdirSync(directory);
  const receiptPath = join(directory, "receipt.json");
  const receipt = {
    attemptId,
    caseId: "approved-smoke",
    disposition: "prepared",
    amountMinor: 100,
    currency: "CZK",
  };
  writeFileSync(receiptPath, JSON.stringify(receipt));
  assert.equal(
    preparedSandboxCase({ root: f.root, attemptId, caseId: "approved-smoke" })
      .receipt.attemptId,
    attemptId,
  );
  writeFileSync(
    receiptPath,
    JSON.stringify({
      ...receipt,
      disposition: "uncertain",
      dispatchedAt: "2026-11-06T12:00:00Z",
    }),
  );
  assert.throws(
    () =>
      preparedSandboxCase({
        root: f.root,
        attemptId,
        caseId: "approved-smoke",
      }),
    /no_replay/,
  );
});

test("lost refund response blocks a new command without deleting its receipt", (t) => {
  const f = fixture(t);
  writeFileSync(
    join(f.root, "refund-old.json"),
    JSON.stringify({ state: "uncertain" }),
  );
  assert.throws(
    () => reserveSandboxRefund(f.root, "new", { state: "dispatched" }),
    /previous_refund_unresolved_no_replay/,
  );
  assert.equal(
    JSON.parse(readFileSync(join(f.root, "refund-old.json"))).state,
    "uncertain",
  );
});
test("accepted refund permits another explicit command and each command is single-shot", (t) => {
  const f = fixture(t);
  writeFileSync(
    join(f.root, "refund-old.json"),
    JSON.stringify({ state: "accepted" }),
  );
  const path = reserveSandboxRefund(f.root, "new", { state: "dispatched" });
  assert.equal(JSON.parse(readFileSync(path)).state, "dispatched");
  assert.throws(() =>
    reserveSandboxRefund(f.root, "new", { state: "dispatched" })
  );
});
