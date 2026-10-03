# Tab deep links - local validation (2026-10-03)

Worktree: `/tmp/festapp-tab-deep-links`, detached `main` base `3912447c8`. Original release worktree and the separately occupied main worktree were not edited. The original breadcrumb strut fix is included. No commit, push, deployment, production writes or tenant rollout.

## Checks

- Router generated exclusively with `fvm dart run build_runner build --delete-conflicting-outputs`. Final generation succeeded.
- Flutter: initial combined batch **128 passed**; follow-up combined batch **131 passed**, followed by **10 passed** object-route cases including one additional bank regression (132 distinct passing cases). Targets: `test/components/navigation`, `test/startup/app_router_deep_link_test.dart`, `test/startup/router_service_post_login_test.dart`, `test/startup/app_bootstrap_test.dart`, `test/router_reserved_paths_test.dart`, `test/components/occasion/occasion_home_navigation_contract_test.dart`, `test/components/users/google_login_panel_test.dart`, `test/components/schedule/light_timeline_initial_day_test.dart`, `test/components/schedule/schedule_initial_day_test.dart`, `test/components/timeline/advanced_timeline_day_list_test.dart`.
- JS: `node --test web_client/tests/core/router_service.test.js web_client/tests/core/google_auth_service.test.js web_client/tests/core/auth_bridge.test.js`: 46 passed.
- Scoped Dart analysis covers changed/new source and test files. Existing `MyApp.isTimeTravelVisible` immutability warning in `main.dart` remains; generated NewsForm editorOverride also carries an existing visible-for-testing annotation warning when analyzing generated code. No newly introduced errors/warnings.
- `git diff --check` passes. Scoped state inventory confirms deletion of old administration controllers, widget registry, selected form/pool and unit menu authorities. Calendar controllers, transient new bank dialog, mobile ticket panel and form/canvas element selection are presentation exceptions.

## Actual browser history

The Chrome widget test runner does not propagate platform routing into actual window history. Its attempted history checks were replaced with a running fixture, not counted as passing browser evidence.

Fixture: `fvm flutter run -d web-server --target test/browser/navigation_smoke_app.dart --web-port 4397 --web-hostname 127.0.0.1`.

Use an explicit empty configuration (`{}`) and `agent-browser --config /tmp/festapp-tabs-browser-config.json --headed false --session festapp-tabs-isolated-20261003`. The workstation global provider is Panerelay: initial checks discovered it connecting to shared browser state despite the session name; that agent daemon was stopped and the checks below were repeated in a separate real headless browser. Do not rely on a session name alone for isolation here.

Verified with actual platform URL and accessibility selection:

- `/occasion-a/reservations/orders/history` direct load selects History.
- Clicking the active History tab leaves browser history length unchanged (2).
- Clicking Current changes URL/content and adds one history entry (3).
- Browser Back restores History URL/selection; Forward restores Current URL/selection.
- Physical reload keeps Current URL/selection.
- `/calendar?day=2026-10-03&preview-day=2026-10-10` direct load selects 3 October.
- Clicking 10 October updates `day` while preserving `preview-day`.
- Browser Back/Forward restore matching date/query/selection; physical reload keeps 10 October.

The fixture uses the actual shared scaffold, access boundary, day binding and native AutoRoute/platform navigation, with in-memory content and no backend writes. Actual form/pool/bank membership boundaries and canonical Back are exercised by widget tests using injected loaders. All production route declarations are checked by the matcher suite.

## Full app against disposable local Supabase

A follow-up run created project `festapp-tabs-e2e-backend` outside the repository on loopback API 56521/DB 56522, PostgreSQL 15, Supabase CLI 2.111.0. Applied the canonical baseline, 82 newer migrations, seed and `test/fixtures/navigation/tenant.sql`. Existing SQL test containers and production systems were untouched. The full real UI entry is `test/browser/full_app_e2e.dart`; it guards the local backend, enables semantics and stubs only the external push identity callback API. Auth, REST, membership RPCs and ticket preview use the real local stack. Production notification/backend requests were aborted in separate local headless browser sessions.

The full-app run exposed a Flutter web transport bug: nested login query escapes were decoded by the engine before browser history, losing preview-day on reload. `PlatformRouteParser` compensates at the native transport boundary; URL-preserving code uses the encoded `urlState.uri`. Three new tests reproduce the engine decode and round trip reserved characters, repeated query values and native-platform behavior.

Verified full-app behavior:

- Anonymous direct link to the second form Responses preserves both dates in the encoded login return target, including login-page physical reload; password login lands on the entire requested URL and actual E2E Second Form Responses screen.
- Form Responses direct load/reload, Orders History and occasion Info/Songbook select the matching real tab.
- Orders active-tab click adds no history; changing to Current, browser Back, Forward and physical reload restore matching URL/content. In this debug session the Current interaction used the actual DOM semantic click handler after CDP pointer clicks did not change state; no router/history mutation was substituted.
- Local pool 1 Settings displays its actual configuration. Foreign form and pool links display controlled denial/not-found without their editor content.
- Mobile width 390: saved schema-version-2 ticket layout opens Properties from `panel=properties`; physical reload preserves the URL and reopens the same panel. Real preview Edge runtime needs static font inclusion in its virtual filesystem, configured with functions.preview-ticket-layout.static_files. The synthetic layout uses registered bundled fonts.
- Unit 1 / bank 1 Users direct load and physical reload show E2E Bank Account; detail Back produces the canonical /unit/1/edit/bank-accounts list. Bank 2 from another unit is rejected. Unknown reservation section stays local Not found; disabled Blueprint on occasion B replaces the path with orders/current.
- Restricted synthetic viewer password login returns to the protected URL and displays Access denied; live semantic DOM has no administration tabs. Screenshot confirms the denial where the accessibility snapshot omitted static text.

A bank detail check revealed redundant reliance on transient global unit state during context refresh. Membership now uses the loaded route UnitAdministrationScope and its unit-filtered RPC list; the enclosing UnitAdminPage continues to gate rights/visibility. Its new regression and the existing foreign-account tests pass (10 object-route tests). The final combined batch before this focused correction passed 131 tests; together with the new regression, 132 distinct Flutter cases are covered. The final JS batch again passed all 46 cases after installing this worktree's npm dependencies. Scoped analysis of the added parser, real E2E entry and bank correction reports only style infos, no errors/warnings.

Startup/accessibility observations, Colima shared-path constraints, required Storage/Edge services, push callback stubs and cleanup commands are captured in the canonical `miakh/development-tools` skill `vendor/codex-skills/festapp-local-e2e` and browser isolation guidance. Installed skills point to those canonical sources.

## Remaining scope

The focused full-app checks above use synthetic local data and do not cover every administrative screen or a live Google OAuth broker. Real calendar browser history/date selection remains covered by the isolated running fixture; the full-app timetable date rendering was not established in this run. Live Google OAuth needs an authorized external account and configured local broker credentials. Full `automation/test_all.sh` and release/deploy gates were not run because publication/release was not requested. The implementation and targeted contract checks are complete; these are validation limitations, not claimed production evidence.

Cleanup completed: both named local browsers closed, the owned Flutter web server quit, functions serve terminated and only the disposable Supabase project stopped with --no-backup. Existing PostgreSQL test containers remain running. No production writes, commit, push or deployment.

## Authorized live release preparation

The user subsequently authorized deployment specifically to live.festapp.net. Rebased the feature onto authoritative main c84030bfc28563aa28bf32d09ea123ef00d2083d, preserving its new occasion report and ticket editor changes. The only content conflict was resolved by keeping the new report and reading the inherited occasion route parameter. Added a nested-report regression and migrated the existing administration presentation test to RoutedTabDefinition.

Release checks: full Flutter 1,012 passed / 1 skipped; web 208 passed; isolated SQL 102 passed; Deno Edge 216 passed; worker integration 3 passed / 27 skipped (external worker inputs absent); automation checks passed. The local SQL fixture was rebuilt using the canonical bootstrap default-privilege reset before baseline restoration. Scoped merge analysis has style/dependency infos only, no errors/warnings.

Main is protected and publication uses PR #253. Production scope is exclusively prod/festapp, Cloudflare project festapplive, version 0.20.70+554. Local production preflight correctly refuses to build without FESTAPP_RELEASE_MANIFEST. The established GitHub Deploy workflow supplies the approved tenant-specific manifest; no private release contract was fabricated and no other tenant is being built or published.
