# Tab deep links

AutoRoute is the navigation owner. `navigation_paths.dart` contains stable English slugs; translated labels and ordering never identify a route. `RoutedTabDefinition` pairs a typed child route with presentation metadata. `RoutedTabScaffold` uses `AutoTabsRouter.tabBar` and its library controller. Clicking an active administration tab is a no-op; public home reselection keeps its existing reset behavior.

## Paths and state

- `/:occasionLink/admin/:section/:subsection` for occasion administration.
- `/:occasionLink/reservations/:section`, including `orders/current|history`.
- `.../forms/:formLink/editor|settings|design|responses` and `.../inventory-pools/:poolId/occupancy|rooms|settings`.
- `/unit/:id/edit/occasions|users|quotes|email-templates|settings|bank-accounts` and `bank-accounts/:accountId/general|connection|users`.
- `day=YYYY-MM-DD` is the selected occasion calendar date. `preview-day` belongs to embedded program previews. `panel=elements|properties` belongs to the mobile panel of an existing saved ticket layout. Query writes preserve other parameters and the whole object path.

Entry paths without a section/subsection select canonical defaults. Known disabled sections replace the URL with the first available section before constructing protected content. Unknown sections remain local not-found pages. The tab container is an empty-path child of a native stack, with a sibling wildcard: AutoRoute tabs ignore unmatched children, so putting a wildcard inside the tabs would lose local errors after a tab was activated.

Occasion boundaries load route context and check access before mounting the nested router. Revoked access hides previously authorized retained editors behind a denial screen; restored access keeps their native stack and drafts. Initial denial never constructs protected children. Unit administration restores unit context after returning from an occasion. Object details validate membership in the route occasion/unit before constructing editors. Generation checks reject stale asynchronous results. Authentication preserves the entire safe internal return URL, including suffix and query, through ordinary and Google login and the JS/Flutter handoff.

## Web query transport

Use `root.urlState.uri` for query-preserving URLs. AutoRoute's `currentUrl` decodes reserved characters and can split nested return targets. `PlatformRouteParser` preserves query escapes across Flutter 3.47's web route-information transport, which decodes them once before the URL strategy. Native platforms keep the default representation. AutoRoute continues to own parsing and browser history; the adapter writes no history itself. Regression tests reproduce that engine transport, including repeated values and reserved characters. Recheck the engine behavior when upgrading Flutter.

## Retention and leaving editors

Native tab routers retain visited content. Object identity belongs to path parameters, with a real list route and typed relative pushes to details. Detail Back confirms drafts and replaces the object stack with its canonical list, including after a direct link. `NavigationDraftBoundary` registers existing editor dirty checks and discard prompts. Switching retained subtabs preserves drafts. Object/occasion replacement and incoming browser routes confirm before AutoRoute removes their pages.

Use the nearest router for typed nested object navigation. External absolute entry URLs use `root_route_navigation.dart`: the installed AutoRoute path lookup starts in the closest scope, where nested wildcards would capture them. Unknown URLs preserve native matches rather than reconstructing wildcard paths as literal `*`. No application code writes browser history.

## Adding a tab

Declare the leaf page with `@RoutePage`, register its stable path in `app_router.dart`, and add a `RoutedTabDefinition` using that typed route to the feature shell. Gate metadata with the existing feature/rights policy. For a tab with subtabs, use a native `AutoRouter` boundary with an empty-path tab shell and a sibling not-found route. Regenerate with `fvm dart run build_runner build --delete-conflicting-outputs`; never edit `app_router.gr.dart` manually.

## Presentation exceptions

Calendar views keep presentation controllers bound by `RoutedDayBinding`; URL state drives their selection and session values only supply a fallback when no valid date exists. Unit side-menu selection reads the library tab controller. New unsaved bank accounts and ticket-layout dialogs remain transient. The mobile ticket panel has query state; desktop does not reopen it. Form-field and canvas-element selection are editor state, not navigation. Existing public home navigation remains on its established routes.

Behavioral coverage lives in `test/components/navigation`, startup/post-login tests and `web_client/tests/core/router_service.test.js`. The isolated browser fixture `test/browser/navigation_smoke_app.dart` runs real AutoRoute/platform history without backend access. Flutter's Chrome widget test runner does not propagate platform navigation into browser history, so browser Back/Forward/reload use this running fixture in a named headless agent-browser session with an explicit empty `--config` (the workstation default uses Panerelay).

For real UI checks with synthetic local Auth/REST/Storage/Edge data, use `test/browser/full_app_e2e.dart` and `test/fixtures/navigation/tenant.sql`. The E2E entry refuses the production backend and mocks only external push identity callbacks. Follow the installed `festapp-local-e2e` runbook for disposable backend setup, static font packaging and owned-resource cleanup. Full-app results and external OAuth limitations are recorded in `docs/plans/evidence/tab-deep-links-validation-2026-10-03.md`.
