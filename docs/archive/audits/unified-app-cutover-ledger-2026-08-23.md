# Unified application cutover ledger — 2026-08-23

This ledger freezes the fetched source ranges and classifies every divergent commit exactly once. The machine-readable per-commit path inventory is [unified-app-cutover-commit-inventory-2026-08-23.tsv](unified-app-cutover-commit-inventory-2026-08-23.tsv). Run `node automation/verify_cutover_ledger.mjs` to prove coverage and uniqueness.

## Fixed points

| Ref | SHA |
|---|---|
| `main` | `d071cdd16be4e500b8c1fa16ac2ad070cbf60fe7` |
| `prod/csmostrava2026` | `84c1d5de5277d4388c25d07235700a93668345c4` |
| `prod/hvezdamorska` | `942c45401b73eaf289bd6f299c606eda4b16cc26` |
| `origin/main` | `d640434ede99be1e1d4438466f1fcdde7cbc6fba` |
| `origin/prod/csmostrava2026` | `dbd06e0fffb7e905885de7724873ab632cbb310c` |
| `origin/prod/hvezdamorska` | `591c6665057c995f842c522ce1c6d010a127ab19` |

- Ahead/behind at the frozen refs: main `0	5`; CSM `0	3`; HM `0	8`.
- Dirty CSM snapshot: `/tmp/festapp-unified-cutover.p9Dm64`; tracked patch SHA is recorded in `tracked.patch.sha256`, and all 15 untracked files are recorded in `untracked.sha256` without exposing file contents.
- Integration worktree: `<temporary-cutover-worktree>`, branch `cutover/unified-main-prod-branches-20260823`, based on `d071cdd16be4e500b8c1fa16ac2ad070cbf60fe7`.
- Initial copied plan SHA-256: `b12aad8d0ef3e264b1806802f50f9853b052a8df9a46cfd52f2f02495c847eeb`; current candidate plan SHA-256 after recording migration-collision evidence and Markdown hygiene: `4d773ce4ec6b94c378d91239cd8063d7d5bacc285e3cbef71856c1bbd603f0db`; execution prompt SHA-256: `88df0e05964e0cc3caf11e3a0851bca468315008177c8438c36dd4e97580739c`.
- Local pre-cutover refs preserve both frozen tenant tips: `backup/prod-csmostrava2026-pre-cutover-20260823` at `84c1d5de5277d4388c25d07235700a93668345c4` and `backup/prod-hvezdamorska-pre-cutover-20260823` at `942c45401b73eaf289bd6f299c606eda4b16cc26`. Pushing those refs remains separately authorized.
- The private configuration repository at `<private-config-repo-root>` owns the
  fail-closed CSM store provisioning contract and canonical publishing data
  without committing release credentials. Legacy tracked runtime env files
  were removed from its current tree while preserving ignored local operator
  copies; their historical values require external rotation.

## Dirty topic transfer

| Bucket | Source inventory | Destination |
|---|---|---|
| occasion permissions | occasion settings state, permission tests, four forward migrations | main candidate; transferred byte-identically |
| speakers counseling | speaker command/editor/DB changes, deletion RPC, tests, forward migration | main candidate; transferred byte-identically |
| order command identity | send-ticket-order identity helper/tests plus JS contract test | main candidate; transferred byte-identically |
| HM product description | `form_models.js` and regression test | main candidate; transferred byte-identically |
| plan artifacts | plan and execution prompt | main candidate; SHA-256 verified |
| other user work | client sync SQL contract edit | main candidate; retained in tracked patch and transferred |

The original dirty worktree remains untouched and is still the primary recovery copy until an authorized main commit exists.

## Classification summary

| Tenant | already-equivalent | promote | generalize | tenant-overlay | operational-only | obsolete-by-revert | Total |
|---|---:|---:|---:|---:|---:|---:|---:|
| csmostrava2026 | 0 | 188 | 0 | 33 | 9 | 30 | 260 |
| hvezdamorska | 0 | 0 | 100 | 32 | 4 | 54 | 190 |

Classification is behavior/tree based and pinned to the immutable SHAs above. Every first-parent path has its own action and candidate relation, including mixed commits; commit status is only a summary of those path decisions. Patch-equivalent commits are `already-equivalent`; reverted or non-surviving effects are `obsolete-by-revert`; surviving config/assets/operational paths are overlays; CSM shared paths are promoted; HM shared paths record whether the candidate blob is exact or superseding. The TSV also records target symbols and the concrete component command that proves retained behavior. The disposable baseline applied all forward migrations and the complete database gate passed 76/76.

## Runtime reachability owners

| Entry point | Canonical owner | Proof |
|---|---|---|
| Flutter routes/features/services | main `lib/**` and generated router | route/feature searches plus Flutter tests |
| Web routes/forms/PWA | main `web_client/src/**`, `web/**`, PWA generators | web and PWA tests; tenant matrix |
| SQL/RPC | main `database/functions/**` and forward migrations | RPC caller search and disposable DB tests |
| Edge endpoints | main `supabase/functions/**` | invoke-string search and Deno tests |
| Workers | main `workers/**` | worker tests and target config boundary |
| Tenant identity/assets | branch source overlay + `apply_config.sh` generated leaves | main-owned exact-content replay gate |

## Retained boundaries and pending evidence

- CSM store screenshots, legal/release metadata, offline map data and incident recovery SQL remain namespaced tenant data; they are not shared runtime or automatic migrations.
- HM/CSM public build identities and branding remain overlay inputs. Generated code/config is not an independent business implementation.
- The historical `generate-hvezdamorska-agreement` endpoint has no caller or runtime path in the main candidate; `generate-order-agreement` is the sole source endpoint. Production deployment and removal of any already-deployed legacy function remain separately authorized release operations.
- Production migrations, deploys, releases, commits, pushes, backup-ref pushes and external branch protection/readback are unapplied.
