# Editor drafts, form loading and order-email presentation

Status: shared SQL and vstupenky.online frontend ACTIVE at 0.20.90+574, including the requested prepared Flutter library upgrade. Scope: shared backend and only vstupenky.online frontend.

Prepared editor changes were ported from the existing workspace onto current main, preserving newer canonical routes, ticket editor/save behavior and reports. Shared EditorActionBar/EditorSnapshot and EditorDraftScope track nested edits and HTML drafts, disable unchanged actions, confirm discard and reload embedded editors without navigating away. Coverage includes forms, design/settings, blueprint, inventory, occasion features and schedule. Rendering design/schedule defaults no longer mutates form data. Existing retained-navigation guards remain in place.

The reported form link resolved to form 59 in organization 3. An existing authorized editor receives code 200, but the deletion-eligibility field query exceeded a 15-second read-only statement timeout with JIT disabled. Repeated correlated product/order-history scans caused an excessively expensive read. The replacement materializes current occasion/form orders and product usage once, and reuses calculated product metadata for field checks. As subsequently requested, historical snapshots alone do not block deletion: both get_form_for_edit and update_form_internal_v1 use current order data/references, retaining permissions, locks and transactional rechecks. History is preserved. The public command wrapper and its grants are unchanged.

The form editor handles failed/null loading with an error state and Retry instead of an endless spinner. Order email history shares the Orders order-symbol column factory, so symbols use the same text formatting without numeric thousands separators. States use the existing OrderStateDisplay with semantic theme colors; filter values and read-only behavior remain unchanged.

Migration: 20261004133000_form_editor_read_usage_performance.sql, exact canonical get_form_for_edit and update_form_internal_v1 bodies. Before production application: verified authoritative main, fresh protected dump/catalog/digests, before-function definitions, atomic SQL/ledger transaction and PostgREST notification. No production fixtures or bulk e-mail sends.

Validation: full automation/test_all.sh passed (110 SQL files, 1069 Flutter tests with one skip, 242 Deno tests, web/automation checks and three local worker integration tests; 27 remote credential-dependent cases skipped). Targeted editor/history tests passed (91 tests). Current-state SQL regression went red on the previous implementation and green on the replacement, covering historical-only fields/products, current usage, permissions, rollback and other references. Final loading/design widget checks include existing configured colors. Changed-file analysis has no errors; two existing warnings remain in contract_feature and EventEditPage. Production evidence will be appended after completion.


Canonical merge: main `31c421fd6da2b4b5ac93c879d60318326a750a74` (PR #282). Migration `20261004133000` was applied with its ledger atomically after a fresh protected backup/catalog/hash and comparison of unchanged before-function definitions. Evidence: `/var/lib/festapp-rehearsal-evidence/editor-form-loading-20261004`. PostgREST was notified. A read-only authorized-editor request for the reported form returned code 200, nine fields and 19 products in **47.677 ms**, within a five-second timeout. Both read/save functions exclude orders_history; private internal execution remains denied to anon/authenticated. No historical records were changed.

Frontend candidate: `0.20.89+573`, production `75d426bb3d18d6bc8d971cc9ce2ee4b53874da86`, exact main base above. Tenant drift check passed; deployment run `37196706049` dispatched only for prod/festapptickets.

Final prepared-change inventory found two additional small changes: read the app-bar page route from its original page context, and expose ticket confirmation only when the ticket feature is enabled. These are included in the sequential follow-up release. The existing report implementation, released form/product changes and invitation-column placement remain canonical. Changes subsequently appearing in other active workspaces are not copied as unfinished work.


The `0.20.89+573` workflow succeeded. Independent public proof at `2026-10-04T10:57:48.445Z` verified the versioned bundle, discard confirmation, Orders email-history route and deletion payloads, with no standalone Email route. Bundle SHA-256: `775f6fd1b7052b4c4a94ede72b9c31b7d5a350e7985a4dc5aa2548ad356c2fad`.

The user additionally requested the already-prepared Flutter library upgrade in the final release. Ported its pubspec/lock and corresponding file-picker API updates onto fresh main, preserving canonical shared-grid behavior. Dependencies include Supabase Flutter 2.18.0, Trina Grid 2.3.0, shadcn_ui 0.55.1, file_picker 11.0.3, Sembast 3.8.11/2.4.6, HTML/image/cache/scanner updates and their locked transitive dependencies. Added the supplied real on-disk offline-storage reopening regression; no new package versions were independently selected.

Library validation: full Flutter suite passed with the upgraded lockfile (1070 tests, one skip), including Auth recovery, standard grids, HTML editing, forms/tickets and the new on-disk storage regression. Targeted analysis has no errors/warnings; diff check passed.


Final library release candidate: main `9158a4d5bad6aab026d2c19aa95bfc318873663b` (PR #284, including navigation/ticket visibility PR #283), production `cd86b3063d4b086c9968ada61b057d222195a06c`, version `0.20.90+574`. Tenant drift gate passed; only prod/festapptickets was pushed and workflow `37197266898` dispatched after verification of the preceding release. No other tenant frontend was built or deployed.

Fresh read-only server inventory confirmed no old gateway container/image, email_capacity.worker_url selecting only the Edge queue processor and paused=false. Previously confirmed owner plain/PDF receipt remains the end-to-end sender evidence; this rollout changes no sender path.

Final deployment run `37197266898` succeeded, including the canonical public coherence checks. Independent live verification at `2026-10-04T11:06:50.346Z` confirmed `0.20.90+574`, immutable bundle `main.dart.0.20.90-574.js`, prepared editor/history/deletion code and canonical tenant activation. Bundle SHA-256: `4c085097916f23cbdb46765786cf9c367501a7204d4d3e288acde458580a3e06`. All requested prepared changes are merged and deployed for vstupenky.online; shared form loading and current-state deletion checks are active.
