# Worktree consolidation and API artifact cleanup

Date: 2026-11-14. Source prepared against canonical main
`5b0872c048345bf2aa8ad6a62ff4b48f4382e990`; publication requires protected-branch review.
No production deployment, database migration or history rewrite was performed.

## Consolidation

The two outstanding development branches were already patch-equivalent to main
(PRs #851 and #852). Twenty redundant worktrees were removed after checking
remote reachability or patch equivalence and retaining non-regenerable ignored
files. Full repository refs and all dirty files were backed up outside `source/`.
An independent bare restore reproduced 2,544 refs; restoring the original dirty
files reproduced all 1,786 retained file hashes and the recorded deletions.

The uncommitted public catalogue preview was preserved and analyzed. Outstanding
API webhooks, authorized payment details in admin digests, host/database retention
source, associated tests, drafts and plans were ported into current main sources.
The old build's Docker diagnostic now requires an explicit image instead of its
historical fixed image. Only source was integrated: retention and webhook
production activation were not performed.

Older copies were reconciled against current main rather than merged wholesale.
Current wallet connectors, native browser harness, seating owners, payment/consent
rules, protected OAuth flows, release tooling and immutable migration checksums
remain authoritative. Old seating-transition names, replaced browser-CLI recovery,
renamed migrations and the removed wallet dispatcher were not resurrected. Their
original bytes and residual patches remain in the protected recovery snapshot.
Tenant configuration was preserved in its existing production branches, never
merged into shared main. The original primary checkout remains untouched.
A newly created Slunovrat Android worktree was left to its active owner.

Two existing owner-test defects surfaced during consolidation. The retired
reserved-path definition was removed from the old registry, leaving its current
owner in `reserved_paths.sql`; the historical-byte regression now calls the
actual shared immutable checker instead of a removed assembler API. Applied
migration and baseline bytes were not changed.

## API artifacts

Removed 210 generated JSON/HTML files from the index: 8,438,461 physical text
lines. This is a working-tree/source reduction, not a Git-pack size claim.
Small release approvals and the pinned archive locator remain versioned.
Ordinary generation writes only eight current projections; preparation builds
those projections, restores historical immutable URLs and renders offline HTML.
Make prepares its projection explicitly; Help reads the shared authored facade
metadata and does not need the generated directory. Docker builds from source
in a separate stage and requires explicit source-SHA provenance without `.git`.

All locally reachable historical API snapshots were exported conservatively:
240 files, 355,598,560 raw bytes, 10,531,035 archive bytes. The existing public
GitHub Releases service holds `api-contract-archive-20261114`; content review,
archive-member checks, SHA256 verification and independent download passed.
SHA256: `650962babfd9fc4eef0eda39b77a4a607e2c37ac9af1e2cefec0c79e85ef0b39`.
The released baseline and its original approval are retained unchanged. Runtime
serves local exact bytes, including original immutable ETags and cache policy;
no runtime request fetches or regenerates an archive. Corruption or an unavailable
pinned archive fails preparation/compatibility instead of skipping checks.

The new guard rejects forced additions to the ignored output directory and
newly reachable old artifact history, including an unrelated old branch merged
with the `ours` strategy. Its regression uses real independent Git histories.

## Verification

- 152 selected Node tests, including TLS dispatch, OAuth/runtime regressions,
  event disclosure allowlists, offline references and independent archive recovery.
- 11 actual PostgreSQL/API/TLS integration cases and 2 selected SQL files,
  including current source parity and authorized payment-detail projection.
- 19 source/security contracts; 9 operational-retention tests; 18 CI contracts;
  the Git artifact guard and its forced-add/ancestry regression.
- 12 Make tests, 4 Help tests and 7 localized digest-rendering tests.
- Frozen pnpm 11.24.0 installs; eight generated projections, examples, lint,
  deterministic HTML and released-baseline compatibility passed.
- Targeted Dart analysis of the preserved catalogue preview and settings host:
  no issues. No Flutter build, browser session or product release was requested.

Detailed receipts and the verified recovery bundle are protected under
`~/Library/Application Support/Festapp/maintenance/20261114-history-cleanup/`.
The normal 14-day backup review begins only after all owners are restored; do
not prune the recovery bundle while history migration remains unfinished.

## Remaining gates

Main requires one approved review and forbids force pushes. A new Android
worktree also appeared during the initial consolidation, so a global write
freeze is not established. The historical graph, production refs and active
release worktree were not rewritten. Source publication requires its normal PR
review/CI; a future history rewrite needs a new closed service window, explicit
final ref manifest, supported branch-protection handling and metadata remapping.
No physical hosting GC, clean post-rewrite network clone or full runtime rollout
is claimed. Production branches in the sibling JSON are inventory only.
