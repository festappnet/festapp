# Festapp branch audit before history compaction

Date: 2026-11-03. Read-only inventory against `origin/main = 1d7841dd5ffa2b0d864109e916cd78c2cbcbb621`. No branch was modified or deleted.

Counts are graph differences, not proof of unique source changes. Squashed or cherry-picked fixes can have unique commit IDs but equivalent content. Date is tip commit date, not a reliable last-use date. Old tenants are not automatically obsolete.

The rewrite boundary proposed for the <=3,000 main-commit target is `1beb50e3c92daf904b8e235484d9003aa78845be` (2026-08-31). The ancestry column means the ref contains this boundary; exact rewrite impact also requires inspecting later shared commits.

| Ref | Tip date | Behind main | Unique commits | Contains boundary | Disposition |
| --- | --- | ---: | ---: | --- | --- |
| `origin/feat/admin-mcp-seat-holds-release-20261023` | 2026-10-23 | 617 | 8 | yes | preserve: inspect unique content and patch equivalence |
| `origin/feat/agent-access-20261003` | 2026-10-03 | 1596 | 2 | yes | preserve: inspect unique content and patch equivalence |
| `origin/fix/blueprint-majority-label-defaults-20261022` | 2026-10-22 | 721 | 2 | yes | preserve: inspect unique content and patch equivalence |
| `origin/fix/email-substitution-autolinks-20261019` | 2026-10-19 | 964 | 1 | yes | preserve: inspect unique content and patch equivalence |
| `origin/fix/tenant-startup-test-config-20261103` | 2026-11-03 | 1 | 1 | yes | preserve: inspect unique content and patch equivalence |
| `origin/fix/ticket-editor-ui-20261003` | 2026-10-03 | 1631 | 1 | yes | preserve: inspect unique content and patch equivalence |
| `origin/gh-pages` | 2026-08-28 | 4017 | 593 | no | keep: hosting, verify current consumer |
| `origin/main` | 2026-11-03 | 0 | 0 | yes | keep: canonical |
| `origin/prod/absolventskyvelehrad` | 2026-10-25 | 520 | 94 | yes | keep: tenant, audit ancestry |
| `origin/prod/aksmcz` | 2026-10-18 | 1076 | 64 | yes | keep: tenant, audit ancestry |
| `origin/prod/avapp` | 2024-03-05 | 3599 | 29 | no | keep: tenant, audit ancestry |
| `origin/prod/cavfotofest` | 2026-10-25 | 522 | 80 | yes | keep: tenant, audit ancestry |
| `origin/prod/csmostrava2026` | 2026-10-25 | 522 | 86 | yes | keep: tenant, audit ancestry |
| `origin/prod/doobiscup` | 2026-10-25 | 522 | 82 | yes | keep: tenant, audit ancestry |
| `origin/prod/farnostopava` | 2026-11-01 | 105 | 70 | yes | keep: tenant, audit ancestry |
| `origin/prod/festapp` | 2026-11-03 | 0 | 169 | yes | keep: tenant, audit ancestry |
| `origin/prod/festapptickets` | 2026-11-02 | 2 | 685 | yes | keep: tenant, audit ancestry |
| `origin/prod/festappticketsglobal` | 2026-10-25 | 522 | 9 | yes | keep: tenant, audit ancestry |
| `origin/prod/festivalslunovrat` | 2026-10-31 | 118 | 121 | yes | keep: tenant, audit ancestry |
| `origin/prod/hvezdamorska` | 2026-11-03 | 0 | 146 | yes | keep: tenant, audit ancestry |
| `origin/prod/jubileum2025` | 2026-10-25 | 452 | 63 | yes | keep: tenant, audit ancestry |
| `origin/prod/slunovratopava` | 2024-11-06 | 3190 | 244 | no | keep: tenant, audit ancestry |
| `origin/prod/ticketonline` | 2026-08-30 | 2339 | 336 | no | keep: tenant, audit ancestry |
| `archive/work-in-progress-20261029` | 2026-10-29 | 256 | 2 | yes | preserve: inspect unique content and patch equivalence |
| `backup/main-before-canonical-sync-20261031` | 2026-10-30 | 155 | 1 | yes | preserve: inspect unique content and patch equivalence |
| `docs/shoptet-research-20261029` | 2026-10-29 | 180 | 0 | yes | merged: candidate retirement after worktree/consumer check |
| `fix/hidden-participant-notifications` | 2026-11-01 | 93 | 3 | yes | preserve: inspect unique content and patch equivalence |
| `fix/tenant-startup-test-config-20261103` | 2026-11-03 | 1 | 1 | yes | preserve: inspect unique content and patch equivalence |
| `main` | 2026-11-01 | 102 | 2 | yes | keep: canonical |
| `prod/festapp` | 2026-10-24 | 528 | 162 | yes | keep: tenant, audit ancestry |
| `prod/festapptickets` | 2026-10-29 | 160 | 633 | yes | keep: tenant, audit ancestry |
| `prod/festappticketsglobal` | 2026-10-23 | 615 | 7 | yes | keep: tenant, audit ancestry |
| `prod/festivalslunovrat` | 2026-10-24 | 528 | 111 | yes | keep: tenant, audit ancestry |
| `prod/hvezdamorska` | 2026-10-24 | 528 | 139 | yes | keep: tenant, audit ancestry |
| `release/farnostopava-blueprint-20261101` | 2026-11-01 | 107 | 68 | yes | preserve: inspect unique content and patch equivalence |
| `release/festapptickets-bank-observation-20261102` | 2026-11-02 | 42 | 681 | yes | preserve: inspect unique content and patch equivalence |
| `release/festapptickets-order-detail-focus-20261102` | 2026-11-02 | 77 | 671 | yes | preserve: inspect unique content and patch equivalence |
| `verify/ready-prs-20261102` | 2026-11-02 | 26 | 8 | yes | preserve: inspect unique content and patch equivalence |
| `wip/joomla-listing-20261029` | 2026-10-29 | 180 | 0 | yes | merged: candidate retirement after worktree/consumer check |

## Decisions needed during execution

- Keep main, all production tenants and hosting consumers functional. No tenant deletion or deployment is authorized by this inventory.
- The two fully merged local research/listing branches share tip `00f05276de`; both are attached to worktrees. They are retirement candidates only after checking uncommitted work and their owners.
- The six remote feature/fix branches each have graph-unique commits. None is immediately safe to delete from ancestry evidence alone. Classify with `git cherry`, focused endpoint diffs and current consumers; migrate preserved work onto the rewritten graph without importing original main ancestry.
- Local backup/archive branches contain graph-unique commits. Preserve in the external recovery bundle, inspect for pending work, then retire only under approved ref scope.
- Release branches contain legitimate tenant overlays; hundreds of unique commits do not imply hundreds of unfinished main changes. Check overlay-only differences and the main-owned drift policy.
- The oldest tenant branches lack canonical overlay metadata. Keep their trees/entrypoints intact; modernization is a separate project.
- Four local tags exist: `backup/pre-cleanup-reword`, `backup/pre-msg-rewrite-39d89b478`, `csmostrava2026-v0.19.85+414`, `joomla-vstupenky-online-v1.0.1`. Audit remote tags too; classify backup versus public release tags before any remapping/deletion.
- Refresh this inventory at freeze. Record a final action for every remote/local branch, tag, detached worktree and relevant automation consumer, with exact expected SHA and owner. A preserved ref retaining the old graph must be reported as a storage limitation.

## Execution disposition - verified local candidate

See [execution result](git-history-compaction-RESULT-2026-11-03.md) for exact
old/new refs, retained consumers, proofs and measured sizes. The candidate
remaps only main and the 12 named tenants. The six remote feature/fix branches,
three legacy tenants, gh-pages and the public Joomla release tag remain
unchanged. No remote or shared-worktree ref has been published, moved or deleted.

Feature branches were checked with patch equivalence plus merge-base endpoint
path/diff evidence. The startup fix is patch-equivalent; the seat-hold branch
has four unique and four equivalent patches; the other four have unique
patch candidates. Owner intent remains unassumed: all are retained. Both
local-only main commits are patch-equivalent, but remain externally backed up.

Every original local ref is listed in the external all-local-ref ledger and
bundle. Local archives, backup tags and release branches remain untouched in
the original checkout. The two merged research/listing branches still have
worktrees and were not retired. Dirty work and detached heads were preserved
for all 12 worktrees, with 11 additional worktree archives beyond the main
workspace. Ignored private inputs remain in their untouched original locations.

The full remote clone retains old graph intentionally: eight pinned historical
commit IDs remain active tooling inputs. The retained release/feature refs
provide those IDs, proven in a default full clone and checksum-verified SQL
history extraction. Further storage cleanup requires a separate source-contract
migration before removing/remapping those refs. GitHub Pages still points at
gh-pages; deployment workflows are manual. Original PR refs were advertised
and inventoried externally; their server retention was not changed.

## Final published disposition

The owner-authorized transaction completed. All six remote feature/fix branches
are retired and externally archived. AKH one-off SQL completion was confirmed
by canonical read-only receipts; the disabled broker was archived as abandoned.
The public Joomla tag was retained as a parentless identical-tree snapshot to
preserve native updater/download URLs. gh-pages likewise retains its current
tree in one snapshot. Main and the 12 named tenants are remapped; the three
legacy tenants are untouched. The final result and machine-readable publication
manifest supersede this audit's initial provisional keep/inspect classifications.
