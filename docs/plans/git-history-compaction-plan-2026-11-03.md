# Squash redundant Git history while preserving released source

Date: 2026-11-03
Status: Completed and published. All final remote refs, protections, source
identity, tenant ancestry, fresh-clone measurements and CI are verified. See
[execution result](git-history-compaction-RESULT-2026-11-03.md).
Verification for execution: standard (shared history and release ancestry).

## Outcome and recommendation

Reduce main to at most **3,000 reachable commits**, measured with
`git rev-list --count NEW_MAIN`, including commits reached through merge parents.
Aim for substantially fewer when coherent grouping permits it, while preserving
the current application and the functionality/content of all retained branches.
Audit branches as part of the work; do not collapse the project into one commit.

Preserve history through `1beb50e3c92daf904b8e235484d9003aa78845be`
(2026-08-31), which contains 2,081 reachable commits. Rebuild the subsequent
September-November integration history as meaningful checkpoints. It currently
contains 1,943 reachable / 1,197 first-parent commits. The hard additional budget
is therefore **919** reachable commits; aim for **300-700** coherent checkpoints
(approximately 2,381-2,781 total), subject to the grouping and branch audit.
Do not pad the history to reach this range or sacrifice useful boundaries merely
to hit its lower end. Recompute the budget if the frozen input changes.

The proven October 20-21 interval is the first local pilot, not the entire scope:
its 55 first-parent / 139 reachable commits alone cannot meet the 3,000 cap.

Commit count, working-tree line count and Git storage size are different measures.
Squashing preserves the final tree, so it does not remove current application
code. Removing intermediate blobs can reduce a fresh clone, but only after old
branches, tags and other retaining references are dealt with. Line counts are
not a size estimate: JSON often compresses well and binary assets can dominate.

## Verified starting point

Read-only reconnaissance included `git fetch --no-tags origin`, first-parent
numstats since September, refs/worktrees, tenant metadata and GitHub protection.
These SHA values are observations, not authority to overwrite later commits.

| Fact | Evidence / consequence |
| --- | --- |
| Authoritative main | `origin/main = 1d7841dd5ffa2b0d864109e916cd78c2cbcbb621` |
| Current workspace | `HEAD = a31277e3c3d761ed37d6425a1f2a731584b92e8d`, 2 commits ahead and 102 behind origin/main, plus many tracked/untracked changes |
| Local-only commits | `9de1b856a` and `a31277e3c`; preserve and reconcile explicitly, never assume remote contains equivalent changes |
| Main history | 4,024 reachable commits, 3,002 first-parent commits |
| Since the retained August 31 boundary | 1,943 reachable / 1,197 first-parent commits; 208 first-parent commits change at most 20 textual lines; 51 subjects start with `docs` |
| Local storage | `git count-objects -vH`: packed 896.75 MiB, loose 52.06 MiB; includes other refs and is not main-only or GitHub storage |
| Protection | main disallows force pushes and requires one approving review; no required status checks returned by the branch-protection endpoint |
| Open PRs | `gh pr list --state open` returned none; refresh at execution |
| Existing retention | local backup/archive branches, four tags, multiple active worktrees, remote feature branches and production branches |

### Proven large add/remove interval

- The local pilot preserves original history through anchor
  `48d8b6db0479818b556e3852c7ea50ead4035d11`.
- Candidate interval begins with `3347171258690f5064722f003321a9d3a9be2810`
  (2026-10-20), and ends at
  `7c95f3829825cc1523b54d5e1cd31118210e298d` (2026-10-21).
  It contains 55 first-parent commits, including the two PR merges below.
- `ddd54c61038340c262966aecdd03c8f1035636dc` adds 1,522,512 textual
  lines; `7c95f3829` deletes 1,912,619. These are whole-commit first-parent
  statistics, not a claim that every line belongs to the same feature.
- `docs/plans/evidence/canonical-authorization-20261020/domain-ledger.json`
  has 243,813 lines added and later deleted; `entrypoint-inventory.json` has
  234,021 added and deleted. Both changes occur in those two PR merges.
- Blueprint text fixtures also contain large temporary versions in this
  interval. Keep the final fixture contents, not the temporary serialization.
- The TrinaGrid vendor import is later, at `c288a6fb1` on October 25.
  Its removal in this workspace is uncommitted. The October pilot alone will
  not remove its historical copy. Whether the wider rewrite can remove it depends
  on retained release/base checkpoints; report this separately.

## Scope, decisions and constraints

1. The execution input is a freshly frozen, authoritative main, not this stale
   dirty checkout. Preserve all local changes, including the verified TrinaGrid
   migration. History rewriting must run in a separate disposable clone.
2. The proposed pilot squash replaces the 55-commit interval with one integration
   checkpoint whose tree exactly equals the original interval end. This removes
   at least 54 first-parent entries in that interval; reachable-commit and byte
   savings must be measured on the candidate. Grouping sacrifices intermediate
   bisect resolution and must be visible in the reviewable manifest.
3. Across the September-November range, small commits are candidates when adjacent and part of the same
   logical change, such as an implementation plus immediate correction and
   verification receipt. Size or a `docs` prefix alone is insufficient. Preserve
   independent migrations, fixes and useful feature boundaries. Larger completed
   implementation/followup sequences may become one milestone even if they have
   substantial churn. Group by delivered outcome, not just commit size. Rebuild
   from end snapshots so add/remove artifacts within a group disappear naturally.
4. Preserve exact source trees at checkpoints required by active tenant bases
   and useful releases. A later group cannot cross such a checkpoint unless an
   equivalent intermediate tree is retained. The existing tenant bases are not
   inside the pilot 55-commit interval, so they do not currently split it. All
   bases after the August boundary constrain the wider checkpoint manifest.
5. Flatten rewritten merges into content checkpoints; never retain an original
   merge parent descending from the rewritten interval, since it would make
   the removed history reachable again. Preserve authorship/PR references in
   commit messages or the external old-to-new mapping.
6. Never filter a required dependency out of a historical snapshot and leave its
   pubspec pointing at a missing directory. Removing the later TrinaGrid lifecycle
   requires its own wider, explicitly assessed squash interval.
7. Main's final tree must remain byte-for-byte identical to the frozen input.
   No application refactor, dependency update, migration, build, deployment or
   version bump belongs in the history operation.

## Production ancestry and references

`docs/architecture/tenant_overlays.md` and
`automation/check_tenant_branch_drift.sh:33-38` require `baseMainSha` to be an
ancestor of both canonical main and the tenant tip. Rewriting main changes later
SHA values even if all their trees remain identical. Updating main alone would
invalidate the recorded bases of affected tenant branches.

The following remote branches contain the widened rewrite boundary and need a
coordinated reference/metadata migration if execution is approved:

```
prod/absolventskyvelehrad
prod/aksmcz
prod/cavfotofest
prod/csmostrava2026
prod/doobiscup
prod/farnostopava
prod/festapp
prod/festapptickets
prod/festappticketsglobal
prod/festivalslunovrat
prod/hvezdamorska
prod/jubileum2025
```

`prod/avapp`, `prod/slunovratopava` and `prod/ticketonline`
do not contain the August boundary and remain untouched for this candidate. Refresh
the inventory before execution; do not infer approval for all tenants from this
read-only list. The rewrite is not a rollout and must not trigger tenant builds.

For affected branches, recreate their ancestry against mapped main checkpoints,
preserving branch contents except the mechanical old-to-new `baseMainSha` value.
Map shared main nodes consistently across all branches. Preserve tenant-only
history or squash its own related fixups under the same manifest rules. Compare
all other blobs/modes exactly, including generated assets, configuration, legal
files, binaries and submodules. Do not run apply_config merely to conceal drift.
Existing drift failures must be resolved or explicitly scoped before publication;
never widen the policy or bless unrelated changed tenant source as history work.

## Execution waves

### 1. Audit branches, freeze, reconcile and create an external recovery copy

- Obtain separate execution authority, including the exact main/tenant/ref set,
  reference deletions and temporary protection changes. Local candidate execution
  is now authorized; the result records the remaining publication gate.
- Coordinate a short write freeze with owners of active worktrees and release
  operations. Inventory detached worktrees and untracked/ignored work separately.
- Preserve this workspace without resetting, cleaning or stashing it implicitly.
  Reconcile local-only commits and pending TrinaGrid work through normal source
  integration before choosing the final frozen main, or record them as owned
  pending patches to replay afterward. Do not silently publish them as cleanup.
- Export refs and all reachable objects to a verified bundle outside the repo;
  separately preserve working changes and necessary untracked files. A Git bundle
  does not contain uncommitted work. Keep archive/backup refs in that external
  recovery copy, not on the cleaned remote.
- Save exact ref SHAs, branch protection/rulesets, tenant bases, tag targets and
  CI trigger behavior. Check every tag/feature/gh-pages ref for retention of
  rewritten history; do not delete or move release tags without explicit scope.
- Complete the branch audit started in
  `docs/plans/git-history-branch-audit-2026-11-03.md`. Assign each branch to keep,
  migrate, integrate pending work, external archive or proposed deletion. Check
  patch equivalence and endpoint content as well as graph ancestry, and identify
  hosting/release consumers. A stale date alone is never a deletion reason.

Exit: recoverable source/refs, no active uncoordinated writer, frozen input and
an explicit ref allowlist. No rewrite against moving origin/main.

### 2. Build a reviewable grouping manifest and candidate

- In the disposable clone, construct a machine-readable manifest containing
  each contiguous group's old commits, parents, end tree, rationale, message,
  retained checkpoints and replacement SHA. Add a separate ref-action ledger.
- Use the proven 55-commit interval as an isolated pilot, then build the complete
  manifest from the August 31 boundary through frozen main. Retain pre-boundary
  ancestry. Group feature/integration milestones and adjacent fixups throughout
  that suffix, respecting checkpoint constraints. Count all reachable parents;
  the complete candidate must add at most 919 commits to the retained 2,081.
  Prefer 300-700 meaningful checkpoints if achievable. If checkpoint requirements
  exceed the cap, present a concrete broader-range alternative before publication;
  do not silently deliver more than 3,000 or erase necessary release history.
- Build replacements from exact end snapshots with a controlled parent map
  (Git plumbing or an equivalent scripted rewrite). Replay all later content
  checkpoints with mapped parents and preserve mapped tenant base checkpoints.
- Migrate affected tenant metadata as described above. Inspect strings containing
  old SHA values and classify active machine inputs versus historical receipts;
  update active contracts and retain receipts with an external mapping.
- Do not push a candidate PR branch containing the old graph merely for preview.

Exit: reproducible local candidate, complete old-to-new/ref mapping, unchanged
main tree and tenant contents matching except the declared metadata field.

### 3. Prove content identity, reachability and measured benefit

- Compare `git rev-parse OLD_MAIN^{tree}` and `NEW_MAIN^{tree}`; they must match.
  Compare retained checkpoint trees and tenant diffs as above.
- Run main-owned tenant drift checks against each affected mapped base/tip in
  the isolated clone, respecting the single-Flutter-task rule if any repository
  helper invokes Flutter. No application build is required for identical trees.
- Verify every new parent/base, `git fsck --full`, commit counts and branch/tag
  reachability. Explicitly prove no kept merge/ref reintroduces removed ancestry.
- Compare equivalent fresh full clones containing the same approved ref set,
  with no alternates, shallow/partial history or shared-object dependencies.
  Compact only disposable clones. Report total/first-parent commits and packed
  bytes independently, plus which retained refs prevent further savings.
- Do not run aggressive GC or expire reflogs in this shared active workspace.
  Do not repeat app tests solely for metadata-identical history. If source tree
  identity fails, reject the candidate rather than calling the change equivalent.

Exit: concrete before/after counts, packed-size measurement, identity checks,
tenant ancestry checks, `git rev-list --count NEW_MAIN <= 3000`, and the exact
publication manifest ready for review. The cap is on main, not a count of every
tenant's unique overlay commits. Retained branches must still work and must not
accidentally reconnect eliminated main ancestry.

### 4. Authorized publication and workstation transition

- This wave remains unperformed until separately authorized. Refresh main and
  every target ref immediately beforehand. If any frozen SHA changed, stop and
  regenerate the affected candidate; do not overwrite the new work.
- Respect main's review requirement and inspect rulesets in addition to branch
  protection. Do not assume admin bypass or silently disable safeguards. Snapshot
  and restore any explicitly approved temporary protection change.
- Inspect CI triggers before publication; prevent automatic production build or
  deployment within the separately approved maintenance window.
- Publish only the approved refs with an atomic push, using explicit
  `--force-with-lease=refs/heads/BRANCH:EXPECTED_OLD_SHA` per branch and explicit
  refspecs. Do not use `--mirror`, unrestricted `--force`, or unlisted ref deletion.
  If atomic updates are unsupported or a protected ref rejects the push, stop;
  do not fall back to a partial multi-branch update.
- Read back all remote SHAs, protection settings and mapped tenant metadata;
  verify the fresh-clone graph. No production deployment is part of this wave.
- Owners of existing worktrees should preserve pending work, then adopt fresh
  clones or carefully replay only unique pending commits/patches. Do not merge
  old main back into the rewritten graph. Keep the external rollback bundle.

Exit: remote refs equal the approved manifest, protections restored, active
workspaces have a documented transition and old retention refs are either
approved for removal or explicitly reported as limiting storage reduction.

## Retention ledger and rollback

| Artifact | Intended treatment |
| --- | --- |
| Temporary large intermediate blobs | Unreachable from cleaned approved refs; keep only final snapshot contents |
| Original merged parent graph in rewritten interval | Replace with mapped parents; no old-graph merge bridge |
| Backup/archive branches and backup tags | External recovery bundle; remote/local removal only when separately authorized |
| Release tags / active feature branches / gh-pages | Classify individually; remap or retain deliberately; never silently delete |
| GitHub PR refs, forks, server caches | Report separately; cannot promise immediate physical deletion through ordinary force push |
| Dirty worktree and detached release worktrees | Preserve; migrate through owner coordination, no automated reset |
| Dated release evidence mentioning old SHA | Preserve historical truth; use external mapping for lookup |

Rollback uses the verified external bundle and exact recorded old refs, through
another coordinated leased ref transaction. Restore branch protection even if
publication fails. Check for intervening writes before rollback and preserve them;
never overwrite work produced after cutover. A rollback restores old history and
therefore temporarily reverses the storage/history benefit, not deployed data.

## Completion and remaining limitations

Done requires the manifest, branch-audit disposition ledger, identity proof,
at most 3,000 reachable commits on main and fewer first-parent commits,
measured candidate clone size, valid tenant ancestry, external recovery copy,
verified remote refs and restored protections. Report actual savings; do not
promise a target number before measuring. GitHub may retain objects through PR
refs/forks/caches and server GC; a cleaner main log is not proof of server shrinkage.
The pilot 55-commit squash alone is not completion of this plan.

The original plan-only drafting performed no rewrites or publication. Local
execution has since produced the verified candidate and external recovery copy
documented in the execution result. Remaining blockers are the owner write
freeze and explicit use of the existing admin review exception for publication.
No remote ref, protection or shared-workspace history has been changed.

References: [Git push leases and atomic updates](https://git-scm.com/docs/git-push),
[GitHub history-rewrite side effects and retention](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/removing-sensitive-data-from-a-repository).
The latter is used for Git history mechanics, not to imply a secrets incident or
that GitHub Support will purge ordinary repository bloat on request.

## Expanded execution authorization and corrected premise

The owner approved both ref options and requested completion. The final scope
adds an identical-tree gh-pages snapshot and retirement of the six audited
feature/fix branches plus the Joomla release tag, with complete external backup.
The main protection maintenance transaction and existing admin review exception
are authorized by the continuation following the documented gate.

Removing these refs also removes live tooling inputs pinned to old Git commits.
Therefore a separate prerequisite must preserve their exact checked bytes as
canonical fixtures and adapt only tooling/test input readers. Freeze that
prerequisite tree before the final rewrite: application source/assets/config
remain identical to original authoritative main, all existing historical
checkpoint trees remain identical, and final rewritten main must equal the
frozen prerequisite tree. This supersedes the original whole-tree equality
comparison directly against the pre-prerequisite remote tip. No application
refactor or deployment is authorized by this correction. The expanded scope
and transaction are recorded externally in expanded-scope.md.

## Completion receipt

Execution completed on 2026-11-03: main has 2,661 commits; final packed full
clone is approximately 190 MiB instead of 499 MiB. The six audited working
branches are retired and externally archived. Public Joomla tag identity is
preserved with an identical-tree snapshot because it backs the actual updater.
The public release and downloaded ZIP are unchanged. Main protections restored;
all six automatic CI workflows passed. No deployment or shared-workspace GC.
The result supersedes all earlier pending-authorization or incomplete-audit
statements in this dated plan's original execution waves.
