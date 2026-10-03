# Material 3 cutover - 2026-10-03

## Canonical contract

`ThemeConfig.theme(brightness: ...)` is the single shared Flutter theme
factory. It always uses Material 3. `colorSchemeForBrand` generates the complete
M3 color roles and computes contrasting foregrounds for explicit tenant/form
colors. Tenant seed declarations remain compatible with `apply_config.sh`.
Futura, tenant backgrounds and the light default are preserved.

`AdaptiveTheme` still selects light, dark or system mode. `ThemeConfig` remains
the owner of branding and theme construction; removing M2 does not remove theme
configuration or mode selection.

All shared callers were migrated: startup, application, songbook page/dialog,
occasion prototype and tests. The ticket editor retains its intentional local
M3 palette; its source was not changed. Its M2-parent test fixtures verify that
its local M3 theme overrides an inherited theme, and are not runtime fallbacks.

## Removed and migrated

- Removed `baseTheme`, `darkTheme(baseTheme)`, swatch construction,
  `getMaterialColorFromColor`, `getShade` and legacy bottom-nav color helpers.
- Replaced the occasion `BottomNavigationBar`/items with
  `OccasionNavigationBar` using M3 `NavigationBar`/destinations. Existing tab
  ordering, login gate, news badges, modal search, reselection and retained map
  session/routing callbacks remain in the occasion shell.
- Day-list padding now leaves a 16 px gutter. The shell Scaffold already lays
  out the body above navigation and handles its safe area.
- Shared action buttons wrap and grow for enlarged text; custom form primary
  and secondary foregrounds use the brand scheme's contrast calculations.
- Event header time/place metadata wraps at enlarged text sizes, while the
  collapsed header retains horizontal scrolling.
- Admin app-bar tabs share one implementation with contrasting labels and
  text-scaled height. System bars use explicit platform icon brightness.

## Validation

- 875 Flutter tests passed, with one pre-existing skip. The original 73 targeted
  tests cover: themes, navigation, map retention contracts, badges,
  program, event theme, timeline, form/admin components, Google login and startup.
- The full Flutter run includes ticket-editor coverage and the five new
  metadata regression cases. Web tests, 100 local SQL tests, 212 Deno tests and
  repository automation checks also passed. Integration dependency setup and
  the final tenant release checks are recorded below when complete.
- Targeted Dart analysis: no errors; two existing immutable-field warnings
  (`FormPage.formLink`, `MyApp.isTimeTravelVisible`) and existing informational
  diagnostics remain. The offline browser harness analyzes without issues.
- `fvm flutter build ios --simulator --debug --no-pub` passed after cutover.
- `git diff --check` passed. Focused `lib/` searches found no M2 opt-out,
  swatch factory, old navigation widgets or removed theme entry points.

## Browser and platform scope

`test/support/material_3_smoke.dart` is an offline visual harness using actual
production widgets, a synthetic local session and intercepted backend requests.
It is not an application entry point. It renders program, anonymous event detail,
profile, news form and the production admin tab strip without tenant breadcrumbs.
Run with `fvm flutter run -d web-server --release --no-pub -t test/support/material_3_smoke.dart`; stop the task server afterward.

All 40 fixture states were captured successfully: five screens at widths
320/1280, light/dark, and 100%/200% text. The final event-detail screenshot
confirms the previously clipped duration wraps and stays visible.

Browser automation must use an explicit empty `agent-browser --config` file,
headless mode and a fresh named session. The workstation's default browser
provider is Panerelay, which must not be used for these checks.

The ordinary local application could not load its occasion configuration and
failed in `AppRouter.getDefaultLink`. These checks do not establish a complete
backend-connected application flow. Android compilation/runtime is unverified:
Flutter doctor cannot determine the installed Java version. iOS validation is a
simulator build, not an interactive device check. Backend, SDK, dependency and
web_client behavior are unchanged. Subsequent user instructions authorize a main
merge and a single-tenant release to `live.festapp.net` (`prod/festapp`, Pages
project `festapplive`). Other tenants are outside the rollout scope.
