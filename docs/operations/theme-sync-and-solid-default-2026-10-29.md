# Shared browser theme and solid appearance default

Admin AdaptiveTheme preferences and public `theme` localStorage were independent.
Both clients now use the same `theme` choice (light/dark/explicit auto). Admin
startup gives that value priority over its asynchronously restored private cache;
existing AdaptiveTheme preferences migrate only when no shared choice exists.
Storage events and page restoration/focus synchronize already open browser tabs.
Both admin selectors reflect the current manager, not a stale saved snapshot.
Native app persistence stays with AdaptiveTheme. Scope is the same browser origin.

The reproduced regression was a stored admin light preference under a dark OS:
the public client incorrectly chose auto/dark. Its regression test failed before
the fix and passes afterward.

Validation: 3 Flutter widget tests (bidirectional updates, auto/system changes,
reopening, migration, native behavior), 3 headless Chrome tests against the real
web storage adapter and AdaptiveTheme/web preference plugin, and 4 public JS
runtime tests passed. The Chrome target is explicit:
`fvm flutter test --no-pub --platform chrome --concurrency=1 test/browser/theme_preference_store_browser_cases.dart`.
Targeted analysis found no errors; one existing MyApp mutable-field warning and
existing informational diagnostics remain.

New appearance presets are solid by default. Selecting a preset or font keeps
the current gradient opt-in, so existing saved gradients remain supported and
font selection cannot silently turn a gradient on. An enabled gradient runs from
top-left to bottom-right in previews, public forms, ticket canvas and PDF.
Dormant secondary colors do not tint solid ticket palettes. The appearance
change passed 35 Flutter tests and 2 actual PDF shading-coordinate tests.
No SQL migration or stored event/form rewrite is needed.

Released to vstupenky.online as **0.20.448+953** from canonical main
`2e05dd51bc6c13a751ca6b89ae8fcd26246af1bb`. The complete 106-test web client
suite passed after updating its historical expectation that auto removes the
key; its extended regression proves explicit auto wins over stale admin light
preferences. Canonical local Flutter/web build, PWA/CSP/build verification,
tenant drift/ancestry and three consecutive live version/asset/legal probes
passed. The PDF helper was deployed separately with paused/drained email and
a guarded restart retaining the container, then successful worker/health probes
and restoration of the previous unpaused state. No stored database rows or SQL
were changed. [Release receipt](releases/festapptickets-theme-sync-2026-10-29.json).

Completed implementation/release worktrees were cleaned after publication;
independent ongoing research/QA work stays isolated from main.
