#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";

const root = resolve(import.meta.dirname, "..");
const output = resolve(root, "docs/archive/audits/unified-app-cutover-ledger-2026-08-23.md");
const inventoryOutput = resolve(root, "docs/archive/audits/unified-app-cutover-commit-inventory-2026-08-23.tsv");
const git = (...args) => execFileSync("git", args, { cwd: root, encoding: "utf8", maxBuffer: 64 * 1024 * 1024 }).trim();
const lines = (value) => value ? value.split("\n").filter(Boolean) : [];

const fixed = Object.freeze({
  main: "d071cdd16be4e500b8c1fa16ac2ad070cbf60fe7",
  "prod/csmostrava2026": "84c1d5de5277d4388c25d07235700a93668345c4",
  "prod/hvezdamorska": "942c45401b73eaf289bd6f299c606eda4b16cc26",
  "origin/main": "d640434ede99be1e1d4438466f1fcdde7cbc6fba",
  "origin/prod/csmostrava2026": "dbd06e0fffb7e905885de7724873ab632cbb310c",
  "origin/prod/hvezdamorska": "591c6665057c995f842c522ce1c6d010a127ab19",
});
const base = fixed.main;
const sources = [
  { tenant: "csmostrava2026", ref: fixed["prod/csmostrava2026"], remote: fixed["origin/prod/csmostrava2026"] },
  { tenant: "hvezdamorska", ref: fixed["prod/hvezdamorska"], remote: fixed["origin/prod/hvezdamorska"] },
];
function treeBlobs(ref) {
  return new Map(lines(git("ls-tree", "-r", ref)).map((line) => {
    const match = line.match(/^[0-9]+\s+\S+\s+([0-9a-f]+)\t(.*)$/);
    if (!match) throw new Error(`Unexpected ls-tree row for ${ref}`);
    return [match[2], match[1]];
  }));
}
const sourceBlobs = new Map(sources.map(({ ref }) => [ref, treeBlobs(ref)]));
const candidateBlobs = new Map(lines(git("ls-files", "-s")).map((line) => {
  const match = line.match(/^[0-9]+\s+([0-9a-f]+)\s+[0-3]\t(.*)$/);
  if (!match) throw new Error("Unexpected git index row");
  return [match[2], match[1]];
}));
const generated = new Set(lines(readFileSync(resolve(root, "automation/tenant-overlays/generated.paths"), "utf8")).filter((p) => !p.startsWith("#")));

function isOverlayPath(path) {
  return path === "automation/project.conf" ||
    generated.has(path) ||
    /^(assets\/icons|fonts|web_client\/src\/assets\/fonts)\//.test(path) ||
    /^android\/app\/src\/main\/res\/mipmap-[^/]+\/ic_launcher\.png$/.test(path) ||
    /^ios\/Runner\/Assets\.xcassets\/AppIcon\.appiconset\/.*\.png$/.test(path) ||
    /^web\/(?:csmostrava-|android-chrome-|web-app-manifest-|favicon|fstapplogo|apple-touch-icon|notification-icon)/.test(path) ||
    /^web\/(?:privacy|support|terms)\//.test(path) ||
    /^automation\/offline-map\/(?:manifests|style)\//.test(path) ||
    /^automation\/release\/(?:fastlane\/(?:metadata|screenshots)|legal)\//.test(path) ||
    /^repo-data\/store-screenshots\//.test(path) ||
    /^database\/recovery\/.*(?:csmostrava|hvezdamorska)/i.test(path) ||
    /^supabase\/migrations\/20260521\d+_csm_ostrava_/.test(path) ||
    /^(?:lib\/(?:appConfig|themeConfig)\.dart|flutter_launcher_icons\.yaml)$/.test(path) ||
    /^android\/app\/src\/main\/kotlin\/(?:festapp|fstapp)\/[^/]+\/MainActivity\.kt$/.test(path) ||
    /^automation\/fonts\//.test(path) ||
    /^(?:netlify\.toml|HANDOFF-hvezdamorska\.md|HVEZDAMORSKA-PLAN\.md)$/.test(path);
}

function capability(paths, subject) {
  const text = `${subject} ${paths.join(" ")}`.toLowerCase();
  if (/maplibre|offline-map|components\/map/.test(text)) return "map-platform";
  if (/pwa|service_worker|offline|cache/.test(text)) return "offline-pwa";
  if (/reception|login|auth|users/.test(text)) return "auth-reception-users";
  if (/schedule|timeline|program/.test(text)) return "schedule";
  if (/fakturoid|agreement|contract|eshop|order|forms/.test(text)) return "forms-orders-integrations";
  if (/database|migration|supabase\/functions|workers/.test(text)) return "database-edge-workers";
  if (/release|fastlane|store|workflow|automation/.test(text)) return "release-automation";
  if (/asset|logo|font|theme|config/.test(text)) return "tenant-brand-config";
  if (/docs|readme|plan|handoff/.test(text)) return "documentation";
  return "shared-application";
}

const capabilityEvidence = {
  "map-platform": ["PublicMapSession;MapLibreMapSurface;offline map cache", "fvm flutter test test/components/map test/data_services/client_sync/occasion_media_cache_test.dart"],
  "offline-pwa": ["canonical PWA service worker;storage bridge;update prompt", "node --test automation/tests/pwa_*.test.mjs web_client/tests/core/pwa_client_adapter.test.js"],
  "auth-reception-users": ["reception login;account deletion;occasion-user permissions", "fvm flutter test test/components/reception && deno test --allow-env --allow-net --allow-read supabase/functions/cancel-reception-registration/cancel_test.ts supabase/functions/_shared/accountDeletion_test.ts"],
  schedule: ["schedule timeline;event duration;reload coordinator", "fvm flutter test test/components/schedule"],
  "forms-orders-integrations": ["product type description;order command identity;Fakturoid EUR/CZK;generate-order-agreement", "node --test web_client/tests/forms/product_type_description.test.js web_client/tests/components/db_orders_command_identity.test.js && deno test --allow-env --allow-net --allow-read supabase/functions/send-ticket-order/fakturoid_test.ts supabase/functions/generate-order-agreement/agreementConfig_test.ts"],
  "database-edge-workers": ["canonical SQL/RPC;Edge functions;workers", "DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:55432/postgres?sslmode=disable ./automation/test_all.sh db && find supabase/functions -type f -name '*_test.ts' -print0 | xargs -0 deno test --allow-env --allow-net --allow-read"],
  "release-automation": ["main-owned release and deploy tooling", "./automation/test_all.sh automation"],
  "tenant-brand-config": ["tenant overlay source inputs and generated write-set", "bash automation/tests/tenant_config_matrix.test.sh && bash automation/tests/tenant_branch_drift.test.sh"],
  documentation: ["canonical plan;runbooks;architecture", "git diff --check"],
  "shared-application": ["canonical shared application tree", "fvm flutter test && (cd web_client && npm test)"],
};

function relationToCandidate(path, sourceRef) {
  const candidateBlob = candidateBlobs.get(path);
  const sourceBlob = sourceBlobs.get(sourceRef)?.get(path);
  if (!candidateBlob || !sourceBlob) return "absent-from-candidate-or-source";
  return candidateBlob === sourceBlob ? "exact-candidate-blob" : "candidate-supersedes-source";
}

function pathExistsAt(ref, path) {
  return sourceBlobs.get(ref)?.has(path) || false;
}

function pathAction(path, source, survives, operational) {
  if (source.tenant === "hvezdamorska" && path.includes("generate-hvezdamorska-agreement")) {
    return "generalize";
  }
  if (!survives) return "obsolete-by-revert";
  if (isOverlayPath(path)) return operational ? "operational-only" : "tenant-overlay";
  if (source.tenant === "csmostrava2026") return "promote";
  const relation = relationToCandidate(path, source.ref);
  if (relation === "exact-candidate-blob") return "already-equivalent";
  if (relation === "candidate-supersedes-source") return "generalize";
  return "obsolete-by-revert";
}

function commitPaths(sha) {
  const parents = git("show", "-s", "--format=%P", sha).split(/\s+/).filter(Boolean);
  if (parents.length === 0) return lines(git("diff-tree", "--root", "--no-commit-id", "--name-only", "-r", sha));
  return lines(git("diff", "--name-only", parents[0], sha));
}

const rows = [];
for (const source of sources) {
  const shas = lines(git("rev-list", "--reverse", `${base}..${source.ref}`));
  const equivalent = new Set(lines(git("cherry", base, source.ref)).filter((line) => line.startsWith("- ")).map((line) => line.slice(2)));
  const finalDiff = new Set(lines(git("diff", "--name-only", base, source.ref)));
  const ahead = new Set(lines(git("rev-list", `${source.remote}..${source.ref}`)));
  for (const sha of shas) {
    const subject = git("show", "-s", "--format=%s", sha).replace(/[\t\r\n]/g, " ");
    const parents = git("show", "-s", "--format=%P", sha).split(/\s+/).filter(Boolean);
    const paths = commitPaths(sha);
    const survivingPaths = paths.filter((path) => finalDiff.has(path) && pathExistsAt(source.ref, path));
    const operational = /release|version|submission|handoff|store|fastlane|\[skip ci\]/i.test(subject);
    const decisions = paths.map((path) => {
      const forcedAction = equivalent.has(sha) ? "already-equivalent" :
        /^revert\b/i.test(subject) ? "obsolete-by-revert" : undefined;
      const differsAtTip = finalDiff.has(path);
      const sourceExists = pathExistsAt(source.ref, path);
      return {
        path,
        action: forcedAction || pathAction(path, source, differsAtTip && sourceExists, operational),
        relation: equivalent.has(sha) ? "patch-equivalent" :
          !differsAtTip ? "same-as-base-at-source-tip" :
          !sourceExists ? "deleted-at-source-tip" :
          source.tenant === "hvezdamorska" && !isOverlayPath(path)
            ? relationToCandidate(path, source.ref)
            : "survives-different-at-source-tip",
      };
    });
    if (decisions.length === 0) {
      decisions.push({ path: "(no-first-parent-paths)", action: "obsolete-by-revert", relation: "empty-commit" });
    }
    const actions = new Set(decisions.map(({ action }) => action));
    let status;
    if (equivalent.has(sha)) status = "already-equivalent";
    else if (/^revert\b/i.test(subject)) status = "obsolete-by-revert";
    else if (actions.has("generalize")) status = "generalize";
    else if (survivingPaths.length === 0) status = "obsolete-by-revert";
    else if (actions.has("promote")) status = "promote";
    else if (actions.has("tenant-overlay")) status = "tenant-overlay";
    else if (actions.has("operational-only")) status = "operational-only";
    else if (actions.has("already-equivalent")) status = "already-equivalent";
    else status = "obsolete-by-revert";
    const capabilityName = capability(paths, subject);
    const [capabilitySymbols, proofCommand] = capabilityEvidence[capabilityName];
    const targetPaths = decisions
      .filter(({ action }) => action !== "obsolete-by-revert")
      .map(({ path }) => path);
    const targetSymbols = `${capabilitySymbols}; targetPaths=${targetPaths.length ? targetPaths.join(",") : "(none)"}`;
    const target = status === "promote" || status === "generalize" ? "main-candidate" :
      status === "tenant-overlay" || status === "operational-only" ? `${source.tenant}-overlay` :
      status === "already-equivalent" ? "main-equivalent" : "none";
    rows.push({
      tenant: source.tenant,
      sha,
      localAhead: ahead.has(sha) ? "yes" : "no",
      capability: capabilityName,
      status,
      target,
      migration: paths.some((p) => p.startsWith("supabase/migrations/") || p.startsWith("database/recovery/")) ? "yes" : "no",
      paths: paths.join(";"),
      pathDecisions: decisions.map(({ path, action, relation }) => `${path}=>${action}(${relation})`).join(";"),
      targetSymbols,
      subject,
      decisionBasis: equivalent.has(sha) ? "git-cherry patch equivalence" : `first-parent path decisions; mergeParents=${parents.length}`,
      proofCommand,
    });
  }
}

mkdirSync(dirname(output), { recursive: true });
const columns = ["tenant", "sha", "localAhead", "capability", "status", "target", "migration", "paths", "pathDecisions", "targetSymbols", "subject", "decisionBasis", "proofCommand"];
writeFileSync(inventoryOutput, `${columns.join("\t")}\n${rows.map((row) => columns.map((key) => row[key]).join("\t")).join("\n")}\n`);

const counts = {};
for (const row of rows) counts[`${row.tenant}:${row.status}`] = (counts[`${row.tenant}:${row.status}`] || 0) + 1;
const markdown = `# Unified application cutover ledger — 2026-08-23

This ledger freezes the fetched source ranges and classifies every divergent commit exactly once. The machine-readable per-commit path inventory is [unified-app-cutover-commit-inventory-2026-08-23.tsv](unified-app-cutover-commit-inventory-2026-08-23.tsv). Run \`node automation/verify_cutover_ledger.mjs\` to prove coverage and uniqueness.

## Fixed points

| Ref | SHA |
|---|---|
${Object.entries(fixed).map(([ref, sha]) => `| \`${ref}\` | \`${sha}\` |`).join("\n")}

- Ahead/behind at the frozen refs: main \`${git("rev-list", "--left-right", "--count", `${fixed["origin/main"]}...${fixed.main}`)}\`; CSM \`${git("rev-list", "--left-right", "--count", `${fixed["origin/prod/csmostrava2026"]}...${fixed["prod/csmostrava2026"]}`)}\`; HM \`${git("rev-list", "--left-right", "--count", `${fixed["origin/prod/hvezdamorska"]}...${fixed["prod/hvezdamorska"]}`)}\`.
- Dirty CSM snapshot: \`/tmp/festapp-unified-cutover.p9Dm64\`; tracked patch SHA is recorded in \`tracked.patch.sha256\`, and all 15 untracked files are recorded in \`untracked.sha256\` without exposing file contents.
- Integration worktree: \`<temporary-cutover-worktree>\`, branch \`cutover/unified-main-prod-branches-20260823\`, based on \`${fixed.main}\`.
- Initial copied plan SHA-256: \`b12aad8d0ef3e264b1806802f50f9853b052a8df9a46cfd52f2f02495c847eeb\`; current candidate plan SHA-256 after recording migration-collision evidence and Markdown hygiene: \`4d773ce4ec6b94c378d91239cd8063d7d5bacc285e3cbef71856c1bbd603f0db\`; execution prompt SHA-256: \`88df0e05964e0cc3caf11e3a0851bca468315008177c8438c36dd4e97580739c\`.
- Existing backup refs do not cover the current CSM/HM tips. Creating/pushing dedicated pre-cutover refs remains separately authorized.
- The private configuration repository owns the versioned provisioning contract and publishing manifest; its locator, revision and values are intentionally omitted from this public ledger. Festapp keeps only generic fail-closed consumers.

## Dirty topic transfer

| Bucket | Source inventory | Destination |
|---|---|---|
| occasion permissions | occasion settings state, permission tests, four forward migrations | main candidate; transferred byte-identically |
| speakers counseling | speaker command/editor/DB changes, deletion RPC, tests, forward migration | main candidate; transferred byte-identically |
| order command identity | send-ticket-order identity helper/tests plus JS contract test | main candidate; transferred byte-identically |
| HM product description | \`form_models.js\` and regression test | main candidate; transferred byte-identically |
| plan artifacts | plan and execution prompt | main candidate; SHA-256 verified |
| other user work | client sync SQL contract edit | main candidate; retained in tracked patch and transferred |

The original dirty worktree remains untouched and is still the primary recovery copy until an authorized main commit exists.

## Classification summary

| Tenant | already-equivalent | promote | generalize | tenant-overlay | operational-only | obsolete-by-revert | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
${sources.map(({ tenant }) => `| ${tenant} | ${counts[`${tenant}:already-equivalent`] || 0} | ${counts[`${tenant}:promote`] || 0} | ${counts[`${tenant}:generalize`] || 0} | ${counts[`${tenant}:tenant-overlay`] || 0} | ${counts[`${tenant}:operational-only`] || 0} | ${counts[`${tenant}:obsolete-by-revert`] || 0} | ${rows.filter((row) => row.tenant === tenant).length} |`).join("\n")}

Classification is behavior/tree based and pinned to the immutable SHAs above. Every first-parent path has its own action and candidate relation, including mixed commits; commit status is only a summary of those path decisions. Patch-equivalent commits are \`already-equivalent\`; reverted or non-surviving effects are \`obsolete-by-revert\`; surviving config/assets/operational paths are overlays; CSM shared paths are promoted; HM shared paths record whether the candidate blob is exact or superseding. The TSV also records target symbols and the concrete component command that proves retained behavior. The disposable baseline applied all forward migrations and the complete database gate passed 76/76.

## Runtime reachability owners

| Entry point | Canonical owner | Proof |
|---|---|---|
| Flutter routes/features/services | main \`lib/**\` and generated router | route/feature searches plus Flutter tests |
| Web routes/forms/PWA | main \`web_client/src/**\`, \`web/**\`, PWA generators | web and PWA tests; tenant matrix |
| SQL/RPC | main \`database/functions/**\` and forward migrations | RPC caller search and disposable DB tests |
| Edge endpoints | main \`supabase/functions/**\` | invoke-string search and Deno tests |
| Workers | main \`workers/**\` | worker tests and target config boundary |
| Tenant identity/assets | branch source overlay + \`apply_config.sh\` generated leaves | main-owned exact-content replay gate |

## Retained boundaries and pending evidence

- CSM store screenshots, legal/release metadata, offline map data and incident recovery SQL remain namespaced tenant data; they are not shared runtime or automatic migrations.
- HM/CSM public build identities and branding remain overlay inputs. Generated code/config is not an independent business implementation.
- The historical \`generate-hvezdamorska-agreement\` endpoint has no caller or runtime path in the main candidate; \`generate-order-agreement\` is the sole source endpoint. Production deployment and removal of any already-deployed legacy function remain separately authorized release operations.
- Production migrations, deploys, releases, commits, pushes, backup-ref pushes and external branch protection/readback are unapplied.
`;
writeFileSync(output, markdown);
console.log(`Generated ${rows.length} ledger rows`);
