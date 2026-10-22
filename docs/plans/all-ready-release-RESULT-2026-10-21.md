# All prepared work - integration and release

User explicitly requested a pull request, approval/merge and immediate release of all prepared work, including the local deletion/migration cleanup. Scope is canonical main plus the selected `prod/festapptickets` tenant only.

## Included

- PR #552 (`9fc907a4e`): standing-area admission assignment and real inventory preparation, with retry and undo/save coverage. The PR branch is a merge ancestor of this integration, so its work is included rather than copied partially.
- Completed `task/artifact-reduction-20261021` work: 667 tracked deletions; compact lossless fixtures/catalogs; extracted small authorization fixtures; removal of unused package archives and retired migration/rehearsal/capture tools; replacement safety and recovery contracts; all completed cleanup receipts.
- 34 historical migration files lose only proven redundant definitions. All 219 migration versions remain. [Fresh boundary comparison](../archive/all-ready-release-2026-10-21/history-parity.json) against main `7911f7345` finds identical effective function bodies at every migration boundary (1174 final signatures). Prior local PG17 original/reduced clone comparisons and recovery revisions are recorded in the individual cleanup receipts. No applied migration is replayed on production.
- The completed native-font test fixture fix from its local worktree and the completed client test reliability/performance archive.
- Integration repairs: the new standing UI test now constructs the required occasion flags; the landing test consumes the real single-dashboard contract, initializes its timezone and retains its marker/menu/CAS assertions. The canonical source-parity test is regenerated to include the already deployed setup/delete migration. No application behavior was removed to satisfy tests.

## Inventory disposition

The old root checkout remains heavily dirty and is preserved. Existing committed work in the other completed task branches is already reachable from main. The repair worktree's apparent new email preview files normalize to exactly the current main TypeScript, so they add no missing behavior. Old wizard snapshots are superseded by the current implemented/deployed wizard; they must not overwrite its newer authorization and storage contracts. Unselected card-layout mockups are superseded by the shipped layout and the explicit cleanup of duplicate previews. The separate Plesuj pilot is marked WIP, is not a prepared PR and does not extend this tenant rollout.

## Verification

- Repository artifact/distribution/retirement contracts: 5 passed.
- Migration layout and baseline coverage: passed; baseline unit contracts: 3 passed; canonical source-parser contracts: 9 passed; generator `--check`: passed after explicit regeneration.
- Runtime recovery safety, immutable abuse/Blueprint/order-seating/operations checks, authorization policy generator and canonical operation inventory contracts passed.
- Full client gate and final production build/live evidence are completed before merge/deployment completion and reported with the release receipt.
- Three supplemental historical security-generation checks fail identically on base main `7911f7345` and this integration: the historical server-security assembly, data-security phase digest and `admit_image_upload_v1` header inventory. They are preexisting source/installed-history bookkeeping discrepancies, not new cleanup regressions; their checks and immutable expectations were not disabled or rewritten.

## Publication and rollout

Create one normal integration PR, record the user's explicit approval, then merge using the authorized maintainer path. GitHub cannot create an approval review by the author of the same PR; do not represent an administrative merge as a separate approving review. The repository administrator is exempt from required review enforcement. Production execution is delegated after the merged main SHA is frozen. Build locally and deploy through `automation/deploy_direct.sh`, preserve the previous prod ancestor and main-owned overlay drift checks, and verify version/activation/assets/legal routes. Planned version: `0.20.318+811` from the currently live `0.20.317+810`.

The complete client rerun passed every core, adapter and Flutter test; its inventory then caught a preexisting duplicate registration of the identical inline-name scenario inside a viewport loop that did not use the viewport. That scenario now registers once outside the loop; both actual mobile-layout scenarios remain. The final complete client gate is rerun on this corrected registration before merge.
