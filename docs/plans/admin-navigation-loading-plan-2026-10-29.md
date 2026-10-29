# Remove redundant reads during administration navigation

Date: 2026-10-29
Status: Completed locally and validated
Verification: standard (asynchronous shared notification behavior)

## Outcome and scope

After the application has loaded, opening and revisiting form tabs must perform only the reads needed for that operation. Returning to Responses still refreshes server data. Fix duplicate Responses reads and overlapping notification badge reads. Flutter bootstrap, renderer performance, production deployment and database changes are outside this change.

## Evidence and decisions

- `FormResponsesContent.loadData` loads fields, then its grid loads orders, then `DbForms.getAllResponses` loads fields and detailed orders again. Initial load therefore performs four sequential reads; tab-return refresh performs three. The duplicate helper has exactly one caller.
- `SingleTableDataGrid._refreshOnReturn` already owns legitimate refresh-on-return and protects dirty grids. Preserve this owner and its behavior.
- `NotificationCenterController.refreshBadge` fences stale results but does not share pending work. Configure, foreground transitions and refresh can start overlapping reads.
- `NotificationCenterBell._contextChanged` foregrounds the controller before configuring its destination context. Route and rights notifications independently queue callbacks in the same frame.
- Form selector and detail each read `get_forms_by_link`, but the latter also resolves the requested canonical form identity. These are distinct navigation boundaries, not the duplicated Responses hydration. Do not bypass canonical resolution or introduce persistent form caches. Editor/settings/design have independent editable drafts; preserve their isolation and retained state.

## Target invariants

1. Initial Responses load reads field definitions once and detailed orders once. Each subsequent refresh reads detailed orders once and reuses the mounted tab's field definitions.
2. The same detailed order bundle provides displayed responses, capacity and waitlist order data, filtered to the selected form as before.
3. One pending badge read per controller generation/revision is shared by concurrent consumers. Completed results are not cached; a later refresh reads again.
4. Account/context changes, snapshot acknowledgement, backgrounding, disposal and successful mute changes must reject stale results. New context reads must never await obsolete identity work.
5. Bell route/rights changes within one frame schedule one context reconciliation, preserving any requested invalidation. Configure the destination before resuming polling.
6. Preserve refresh-on-return, authorization, dirty drafts, error recovery, and notification polling intervals.

## Execution

### 1. Responses

Add the same optional loader injection seam used by adjacent form widgets to `FormResponsesContent`. Request detailed orders in its single grid loader and map responses from that bundle and the already loaded fields. Remove `DbForms.getAllResponses` and its unused imports. Keep the shared grid refresh lifecycle unchanged. Add a real-widget regression covering initial load, tab return, manual refresh, full-order options and selected-form filtering.

Exit: one fields/one orders read initially; zero additional fields/one orders read per refresh. Response and waitlist data share the same order objects.

### 2. Notifications

Coalesce concurrent `refreshBadge` calls only while a read is pending for the same generation/revision. Keep existing stale-result and acknowledgement fences. Clear logical pending work when backgrounded and after successful mute so a later read observes the new server state. Add deterministic delayed-response regressions for overlap, fresh subsequent refresh, identity changes, foreground transitions, acknowledgement and mute races.

Coalesce the bell's queued route/rights callbacks and reorder context/foreground application. Retain original invalidation authority and visibility checks.

Exit: overlapping equivalent reads issue one RPC; new contexts and post-mutation reads remain independent; old results cannot update the current badge.

### 3. Validation and handoff

Use existing registered form widget and notification suites; add no new test root. Run the targeted suites plus existing tab-refresh and retained-navigation regressions with `fvm flutter test --concurrency=1`. Run targeted `fvm dart analyze` on changed Dart files. Check for an existing workstation Flutter task before every Flutter/Dart task and wait without stopping another session's work. Record exact commands/results here. No production release is authorized by this implementation request.

## Risks and boundaries

Tests inject transport loaders and exercise real widgets/controllers, not production network latency or browser frame rates. Response columns retain the mounted field definitions as before. No database or RPC wire contract changes are needed. Existing unrelated workspace changes must remain untouched.

## Execution result

Implemented the Responses single-bundle path, removed `DbForms.getAllResponses`, coalesced pending notification badge reads and bell frame callbacks, and preserved tab-return refresh. Regression cases are added to the existing form editor and notification suites.

Execution-prompt follow-up on 2026-10-29 found the implementation already present in the working tree. Review found one remaining pending-work gap: snapshot acknowledgement rejected a pre-acknowledgement badge result but left its future available for subsequent refreshes to join. Acknowledgement now releases that logical pending read as well. The acknowledgement regression explicitly starts a fresh read before the obsolete request completes and verifies the obsolete result cannot restore unread state. The validation commands below were rerun successfully on this final state; the existing unrelated workspace edits were preserved.

The previous workstation Flutter task ended before validation resumed; no other session's process was stopped. The targeted check initially reported two existing unused locals and lint findings in touched files; these were cleaned up before final validation.

Final validation:

```sh
fvm flutter test --concurrency=1 test/components/forms/form_editor_actions_cases.dart test/components/notification_center/notification_center_cases.dart test/components/single_data_grid/tab_refresh_cases.dart test/components/navigation/routed_tab_navigation_cases.dart
```

Passed: 65 tests, including initial Responses load (one field read + one detailed orders read), tab-return refresh (one additional orders read), manual refresh, selected-form filtering, concurrent badge reads, fresh subsequent polls, old-identity completion during a new read, background/foreground, retry after failure, disposal, mute and snapshot acknowledgement races. Existing retained-navigation and dirty-grid protection regressions also passed.

```sh
fvm dart analyze lib/components/forms/db_forms.dart lib/components/forms/views/form_responses_content.dart lib/components/notification_center/notification_center_bell.dart lib/components/notification_center/notification_center_controller.dart test/components/forms/form_editor_actions_cases.dart test/components/notification_center/notification_center_cases.dart
```

Passed: no issues found. Changed Dart files were formatted; scoped `git diff --check` passed. A scoped source search confirmed no remaining `getAllResponses` declaration or caller in `lib` or `test`.

The implementation stage performed no production deployment, commit or push. The subsequent user request authorizes PR publication and merge only; production deployment remains outside scope. This validates request counts and lifecycle behavior through local regressions, not live browser frame rates or production latency. Bell callback batching and destination ordering are statically checked; the injected runtime regressions exercise the controller and real Responses widget.

## PR publication follow-up

The publication branch starts at current `origin/main` (`2095a9ba4`), rather than the original workspace base (`d2ed02f81`). The intervening commits include daily notification batches, personal read state, grouped-order selection and activity visibility. Three overlapping files were merged preserving those upstream contracts and applying only pending badge sharing, context scheduling and acknowledgement invalidation. The Responses files applied cleanly. On this integrated source, `fvm flutter test --no-pub --concurrency=1` with the same four suites listed above passed all 70 tests (including the newer upstream regressions). The six-file targeted analyzer listed above and canonical formatting also passed. Scoped diff whitespace checks passed. Dependencies were resolved in the isolated worktree with `fvm flutter pub get`.

Immediately before publication, upstream advanced to `d04c8242e` (setup wording for events without tickets). That commit was inspected and merged without conflicts; it changes independent setup copy and translations, so the passing targeted regressions remain applicable. Final targeted analysis passed with no issues after adding braces to an upstream notification detail conditional; no behavior changed.
