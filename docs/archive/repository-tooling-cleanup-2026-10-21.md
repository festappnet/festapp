# Completed migration tooling cleanup - 2026-10-21

Local continuation in `task/artifact-reduction-20261021`, based on canonical main
`f4aa0b6edfa688b03937197d74b0506d2ae81db7`. Original dirty checkout and supported application behavior are
preserved. No production connection, database change, tenant operation, commit,
push, publication, or history rewrite is performed.

## Decisions and deletion ledger

- Removed all 18 one-time Blueprint tools for the frozen 2026-10-19/20
  local backends/sibling package artifacts, plus the dependent 1,000-seat profile
  runner. They had no current application/CI callers. Their original qualification
  results remain recoverable; removing local recipes does not remove Flutter,
  JS parity, SQL, package archive-gate or committed browser regression contracts.
- Removed all 26 completed migration rehearsal import/mapping/repair/
  validation/schema/Storage scripts and the two sole remaining historical cloud
  payload-copy/evidence callers. Current runtime, operational registries, source
  retention policy and encrypted backup/recovery paths remain unchanged.
- The PG17 cutover test used just the old importer's two-line always-NULL
  `auth.uid()` staging definition. Moved those exact bytes to its independent
  SQL fixture with pinned provenance. Its previously skipped PG17 test also referenced an already-deleted SQL migration.
  Extracted exactly its existing six-table/four-function projection from last
  source `6f6c5aa5108f0f67e150fb915d4c8bad9612c66c`, preserving all declarations.
  No selected test SQL, isolation, expected result or application Auth implementation
  changed; ordinary checks now need no deleted importer/migration or Git history.
- Split the mixed rehearsal/runtime shell contract: checks solely for removed
  scripts retired with them; all supported backup/restore, public-origin,
  firewall, runtime-switch, promotion, upgrade, deployment and managed-provenance
  checks remain in `hetzner_supabase_runtime_recovery.test.sh`, registered in the
  automation lane. Removed the static canary-only test for the deleted recipe.
- Removed eight older image-migration bulk/URL/HTML helpers and the test only
  for the deleted legacy-writer guard. The retired writer's inventory identity
  stays as a tombstone. Preserved the current recovery parser, sealed copy/
  atomic reference tooling, read-only orphan diagnostic and their real tests.
  Package scripts no longer expose deleted commands; unused cheerio, p-limit
  and Supabase SDK dependencies are removed from this package only.
- Verified the archived cutover inventory covers **450 commits exactly once**
  before deleting its 2.15 MB TSV and fixed-revision verifier. Historical source
  ranges, decisions, limitations and audit conclusions remain in its ledger.
- Byte-compared the three identical occasion previews, retained `index.html`
  plus the distinct `variants.html`, and deleted the other two copies.
- Updated incoming historical links and command-recipe notices. Current
  installation does not require recovering any deleted tool. Expanded the narrow
  repository guard against reintroducing retired paths.

## Recovery and retained boundaries

Original tracked files are recoverable with `git show f4aa0b6edfa688b03937197d74b0506d2ae81db7:<path>`.
For a whole historical subtree, use `git archive f4aa0b6edfa688b03937197d74b0506d2ae81db7 <directory>` into
an isolated temporary directory, or a historical checkout for command replay.
Use a script and its inputs from the same pinned source; do not reinterpret an
old cloud migration as a current installation or perform remote writes by default.
Two Blueprint probe files had local output-path edits from the preceding cleanup;
this phase removes those recipes entirely, and the pinned original source is
sufficient for historical reproduction. Raw source remains in Git history.

Supported recovery parser `automation/image-migration/storage_references.py`,
its release-manifest digest, all current SQL/migrations, active Blueprint snapshot
files and selected archive remain byte-identical. No runtime source or backup/
restore script is deleted to make a source-contract test pass.

## Actual validation and storage measurement

- Archived fixed-revision verifier passed **450 commits classified exactly once**
  before removal; the three candidate HTML copies were byte-identical before
  deleting two. The retained index and distinct variants remain unchanged.
- Supported runtime/recovery shell safety contract passed. Its production-origin,
  ingress, backup/restore, runtime-switch, upgrade, promotion and deployment
  assertions remain exact copies of the corresponding original checks.
- Node artifact/distribution, backend inventory, backup, private-input and sealed
  copy/remote-transport tests: **59 passed, 0 failed, 0 skipped**.
- Image Python suite: **21 ordinary tests passed**; both opt-in real-PG17 suites
  then ran explicitly with **5 + 5 passed**, no DB skips. Disposable containers
  used the pinned PG17 image, no network, no published ports or bind mounts,
  and were removed after the tests. No production database was contacted.
- R2 archive, backup asset-manifest and retention tests: **18 passed**; runtime
  asset-contraction tests: **3 passed** with PyYAML in an ignored local venv.
  Thus **52 Python cases** actually passed, including the ten real SQL cases.
- Orphan diagnostic smoke tests: **2 passed**; its one live-infrastructure audit
  was intentionally disabled and is not counted as verified. No live read was
  needed or authorized by this source cleanup.
- pnpm 11.24.0 dependency update removed only obsolete package entries; lock diff
  has **0 added / 275 removed lines**, with no remaining-version upgrades.
  `pnpm install --frozen-lockfile` passed in the image tooling package.
- Storage-asset generator `--check`, syntax/source checks and `git diff --check`
  passed. Active SQL/migrations, parser/release digest, runtime/backup/recovery
  implementations and immutable Blueprint manifest/receipt were hash-compared to
  the pre-cleanup state and remain unchanged. Previous application parity/build
  evidence is reused for those unchanged inputs; no Flutter task was launched.

Initial explicit PG17 execution exposed the pre-existing missing migration path,
which ordinary discovery had skipped. The independent projection fixture repaired
that missing input without changing SQL assertions, and both final suites passed.
Initial runtime-asset test import required the normal PyYAML dependency; it was
installed only into `.codex-artifacts/tooling-cleanup/python/`, then all three
cases passed. Neither setup issue was counted as a passing check.

Final source scan finds deleted-path references only in absence guards, immutable
fixture provenance and canonical-mutation retirement tombstones. Current scripts,
CI and package commands no longer read or invoke deleted paths. Historical runbook
commands carry explicit pinned-source recovery notices. All owned test containers
and processes exited; no service or server was left running.

Logs are `/tmp/festapp-third-{runtime,node,python,pg17-final,disposition-pg17-final,
recovery,asset-runtime,orphans,storage-generator,pnpm}.log`.

This phase: **62 files removed, 13 modified, 5 added**.
Changed-file source storage: **3,411,421 -> 225,647 bytes**, net
**3,185,774 bytes saved**. LF separators: **11,909 -> 3,427**,
net **8,482 fewer**. Script-source LF separators alone shrink by
**7,765** (comments/blank lines included; this is not a business-logic count).
The two duplicate HTML copies account for **533,670 bytes** of the reduction.
Independent test SQL/provenance and the current runtime contract replace historical
inputs/assertions rather than introducing another application implementation.
These are current-tree measurements; Git history and clone packfiles are unchanged.

The subsequent [cloud-merge cleanup](cloud-merge-tooling-cleanup-2026-10-21.md)
retired the managed-export staging recipe and its source-only assertion. All
current backup/runtime checks above remain supported.
