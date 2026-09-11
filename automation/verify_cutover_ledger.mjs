#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim().split("\n").filter(Boolean);
const file = resolve(root, "docs/archive/audits/unified-app-cutover-commit-inventory-2026-08-23.tsv");
const [header, ...lines] = readFileSync(file, "utf8").trim().split("\n");
const columns = header.split("\t");
const allowed = new Set(["already-equivalent", "promote", "generalize", "tenant-overlay", "obsolete-by-revert", "operational-only"]);
const rows = lines.map((line) => Object.fromEntries(line.split("\t").map((value, index) => [columns[index], value])));
const fixed = {
  main: "d071cdd16be4e500b8c1fa16ac2ad070cbf60fe7",
  csmostrava2026: "84c1d5de5277d4388c25d07235700a93668345c4",
  hvezdamorska: "942c45401b73eaf289bd6f299c606eda4b16cc26",
};

for (const tenant of ["csmostrava2026", "hvezdamorska"]) {
  const expected = git("rev-list", "--reverse", `${fixed.main}..${fixed[tenant]}`);
  const actual = rows.filter((row) => row.tenant === tenant).map((row) => row.sha);
  const duplicates = actual.filter((sha, index) => actual.indexOf(sha) !== index);
  const missing = expected.filter((sha) => !actual.includes(sha));
  const extra = actual.filter((sha) => !expected.includes(sha));
  if (duplicates.length || missing.length || extra.length || actual.length !== expected.length) {
    throw new Error(`${tenant} ledger mismatch: expected=${expected.length} actual=${actual.length} missing=${missing.length} extra=${extra.length} duplicates=${duplicates.length}`);
  }
}
for (const row of rows) {
  if (!allowed.has(row.status) || !row.target || !row.pathDecisions ||
      !row.targetSymbols || !row.decisionBasis || !row.proofCommand ||
      row.paths === undefined) {
    throw new Error(`Incomplete ledger row: ${row.sha}`);
  }
}
console.log(`Cutover ledger coverage passed: ${rows.length} commits classified exactly once`);
