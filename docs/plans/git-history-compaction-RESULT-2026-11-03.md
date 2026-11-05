# Festapp history compaction - completed

Date: 2026-11-03. Verification: standard.
Status: **published atomically, remote readback and live fresh-clone verification passed**.
No remaining publication step or approval. No application deployment performed.

## Final result

- Remote main: `ccb42e2de4ef65a4900df23a8a4993d056c2e664`.
- Main reachable commits: **4,024 -> 2,661**, below the 3,000 cap.
- Main first-parent commits: **3,002 -> 2,385**.
- Preserve all 2,081 commits through the August 31 boundary. The rewritten
  suffix contains 579 outcome checkpoints plus one tooling-input prerequisite.
- All 579 original endpoint trees, all required active-base checkpoint trees
  and all 1,669 tenant-only historical snapshots retain their exact original trees.
- Application source/assets/config/SQL remain unchanged. Main changes beyond
  history are explicitly allowlisted tooling/test readers and original historical
  input fixtures; rewritten main exactly matches frozen prerequisite
  `913c869b32fe3c259427ac419811ebbb04fef56a`.
- All 12 tenant tips differ solely in `automation/tenant-overlay.json`
  `baseMainSha`. Original and mapped drift checks passed for all 12. Their
  passing checks were retained after adding the main-only prerequisite because
  their tips, bases and checker bytes stayed unchanged; ancestry was reverified.

## Storage and hosting

| Full clone measurement | Ref count | Packed bytes | MiB |
| --- | ---: | ---: | ---: |
| Original complete remote ref set | 24 | 523758065 | 499.49 |
| Same final retained ref set, before rewriting | 18 | 523694540 | 499.43 |
| Final published ref set | 18 | 199155041 | 189.93 |

The observed full-clone reduction is **309.57 MiB (62.0%)**.
Every measurement used independent full repositories, no alternates/shallow or
partial history, identical `repack -a -d -f --depth=50 --window=10` settings, two
pack threads and 64 MiB window memory. `fsck` passed. Disposable measurement
copies were removed after recording their receipts; scripts and recovery remain.

`gh-pages` now has one parentless snapshot instead of 600 commits, with the exact
same source tree. GitHub Pages configuration is unchanged. The public Joomla
1.0.1 tag was **preserved**, using a parentless identical-tree source snapshot:
its actual public updater uses the tag and release download URL. Deleting the
public contract would have contradicted preservation of functionality. The
existing release ID and assets were unchanged; downloading the public ZIP before
and after produced the same SHA256:

`8396ed9892ab07791e037a44e0bc1459274c68a6933f6a531f1e90653494ba6f`

## Audited branch retirement

All six audited remote feature/fix branches are deleted, with exact original
commits and content retained in the external recovery bundle:

- MCP holds/swaps: implemented through main integration and later canonical
  seat-order ownership; original released SQL/migrations matched.
- Ticket editor UI: superseded by merged PR #230; editor blob matched that merge.
- Email auto-link experiment: explicitly withdrawn; main contains the supported
  appearance-only replacement. Rejected code was not merged.
- Tenant startup test: merged via PR #720.
- AKH label repair scripts: confirmed applied by read-only canonical receipts
  (three default-label corrections, two bold alignments) and matching revisions.
- Diagnostic broker: explicitly abandoned/disabled draft, not deployed. It is
  archived, never merged or provisioned; existing SSH administration is unaffected.

The three legacy tenant branches remain unchanged. No unlisted ref was deleted.

## Exact published transaction

One atomic push with one explicit expected-old-SHA lease per action: 14 branch
rewrites, one public release-tag rewrite, six branch deletions. No mirror push,
unrestricted force, partial fallback or application release was used.

| Ref | Original SHA | Verified final SHA / disposition |
| --- | --- | --- |
| `heads/main` | `1d7841dd5ffa2b0d864109e916cd78c2cbcbb621` | `ccb42e2de4ef65a4900df23a8a4993d056c2e664` |
| `heads/prod/absolventskyvelehrad` | `4e1f9cafb4731035b73c4b2c8e4ed8d9c23e6d21` | `e7504d0faddf5a69136ac7c16628502b1701bc14` |
| `heads/prod/aksmcz` | `71c2ea7888978db61a89c3ca09853c3b3a0cf013` | `d94a91c270ed00a0a40a1af3def1be4b5b670a70` |
| `heads/prod/cavfotofest` | `1eb560d2b95be90cbfc121ed869e0760354e20d7` | `6d81ea62ea03223c09d7d7e18f446c4788b92d38` |
| `heads/prod/csmostrava2026` | `b8599d06cd281879d98a99af89af747c470680de` | `b174ced7248c7897b4965c00846ae3a68e3ee267` |
| `heads/prod/doobiscup` | `7069de0092b2f6445220cf0b4ccb39d2c6b1b512` | `863ce475d2e9dc89bf30b1bd48a717f394d3013c` |
| `heads/prod/farnostopava` | `5b170c22eecd643c8eb0a8a610ecf20521106c91` | `a59719a29fd08347749d4703c35ad52ae2f4ed35` |
| `heads/prod/festapp` | `d768115998d6008131530c33235d9beabcfff657` | `a88057416aed159c4444b430cf3e9e5782055b7b` |
| `heads/prod/festapptickets` | `bbe485091b1e5a2ea76c9099b644909ca4b5345e` | `127f47e1926c6b33fbd190208841a918f5fe0a5a` |
| `heads/prod/festappticketsglobal` | `8a4eebb9180a8bdcd352ea9bbe8e946e40be7343` | `d6d2fe979dacfdd4022f6b051edc48225af80f59` |
| `heads/prod/festivalslunovrat` | `b3b2750ce7cbea4acac56236a3b5d49f184cae1c` | `f89359611d4ffab7175e74a179ec956e33941bf6` |
| `heads/prod/hvezdamorska` | `8591c48a28ef18bc350939d230765785f2987afe` | `dfd434101a38ebeb368e804d1569bdb3dabfaab8` |
| `heads/prod/jubileum2025` | `6d7dcd18dbcff9146de7a14b2f322d96c851944d` | `20311cf739f6de635113e55a438167cef40d212d` |
| `heads/gh-pages` | `8f31f880a899b5a2db5548cdf9d20775a360e62b` | `b50d910009b9df2f64595925e9b8f377c32a9e04` |
| `heads/feat/admin-mcp-seat-holds-release-20261023` | `94d21814cd2da51623ef6b8fa1546a2bd0870910` | **deleted; archived** |
| `heads/feat/agent-access-20261003` | `81762854a18d2aae0da6de467b00d39311271a99` | **deleted; archived** |
| `heads/fix/blueprint-majority-label-defaults-20261022` | `579ec27082111d51cec5f282650aed40110ea6a5` | **deleted; archived** |
| `heads/fix/email-substitution-autolinks-20261019` | `7affd90dbdc73fe2f84479f1525c170e1a57faaa` | **deleted; archived** |
| `heads/fix/tenant-startup-test-config-20261103` | `c97dfba242ba0ab4dd6db77dccddb0fcaf6fc28c` | **deleted; archived** |
| `heads/fix/ticket-editor-ui-20261003` | `6d49f4d1f9b0b8f663b6e36aed61d72e07c58fbd` | **deleted; archived** |
| `tags/joomla-vstupenky-online-v1.0.1` | `4b06687ce418bb790d6cc34e295dddbb14fc2159` | `e143b897959d702f6932d6f0b8839b18fd8e3e86` |

Main's force-push permission was temporarily enabled; required review count
remained one and the authorized existing admin exception was used. The complete
original protection snapshot was restored in `finally` and read back. Force
pushes are disabled again. Required signatures remained unchanged. All 18 final
remote refs were read back and an independent clone from GitHub passed complete
`fsck`, exact tree/metadata checks and the main 2,661-commit count. None of the
15 rewritten refs reaches an original removed main suffix commit.

## Historical input compatibility and checks

Deleting retaining refs required replacing runtime historical Git lookups with
checked original bytes. The canonical fixture owner retains **1,102 original
paths from ten revisions**, deduplicated into 986 raw objects, with SHA256
verification. The original revision IDs remain provenance, not runtime Git
dependencies. All bytes were compared against original recovery objects.

A full cleaned clone lacking all ten original input commits successfully ran
baseline validation, checksum-verified recovery of 161 SQL files, immutable
ticketing/seating migration checks, both Python and Node readers, and the exact
same predecessor-upgrade SQL command stream. Seven targeted unit tests passed,
including corruption rejection and recovery without Git. All six GitHub CI
workflows for the published main completed successfully.

Two existing maintenance-tool limitations were verified unchanged, not hidden:
the old authorization assembler's full render fails on functions created after
its frozen baseline; the existing storyboard reference-hash check reports
“Original reference asset changed” with both original and new byte readers.
Their source/input bytes and failure behavior were preserved; application CI
and all history-compaction gates passed.

## Workstation transition and recovery

**Use the clean current checkout for new work:**

[/Users/miakh/source/festapp-compacted-20261103](/Users/miakh/source/festapp-compacted-20261103)

It is clean, independent, points at the real GitHub origin, and has 2,661 main
commits. The original `/Users/miakh/source/festapp` remains dirty at
`a31277e3c3d761ed37d6425a1f2a731584b92e8d`, preserving all pending source work,
including TrinaGrid. Remote-tracking refs were refreshed; `pull.ff=only` guards
against accidental old/new history merges. A local `.git/info/` transition
notice records the new checkout and recovery paths. Do not merge old main or
old tags back. Both local-only commits were already patch-equivalent to the
frozen authoritative main; do not blindly replay them. Pending uncommitted work
requires deliberate source reconciliation, outside this history-only operation.

All recovery/evidence is outside cleaned refs in:

[/Users/miakh/festapp-history-compaction-20261103](/Users/miakh/festapp-history-compaction-20261103)

Retained: verified self-contained `recovery.bundle` and checksum, original
workspace/index patches and 451-path archive, backups of 11 additional worktrees
with 96 changed paths, complete old refs/worktree inventory, all mappings,
publication manifest, protection before/after snapshots, CI results, public
release/ZIP before/after, scripts, candidate repo and live post-publication clone.
Ignored private inputs remain untouched in their original worktrees.

Original local archives/backup refs deliberately remain in the dirty source
repository. No reset, stash, clean, GC or reflog expiration ran there. GitHub PR
refs (575 advertised), forks and caches may retain server objects; fresh-clone
reduction is not a promise about GitHub's physical storage reclamation.

Primary machine-readable receipts: `publication-final-result.json`,
`publication-manifest.json`, `final-verification.json`,
`final-measurements.json`, `final-consumer-verification.json`,
`prerequisite-verification.json`, `feature-final-dispositions.json`,
`workstation-transition.json`, and `post-publication-ci.json`.
