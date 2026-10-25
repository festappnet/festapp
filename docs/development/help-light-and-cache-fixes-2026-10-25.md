# Help light theme and cached navigation, 2026-10-25

Two live failures were reproduced after version 0.20.394+895:

- An isolated real Chrome session first loaded `/napoveda/` with HTTP 200, but
  later returned to HTTP 404 while an unconditional Node request still got 200.
  The HTML asset boundary forwarded browser conditional headers to ASSETS,
  received a bodyless 304, and treated `response.ok === false` as not found.
  Help HTML now uses the existing unconditional `serveAsset` HTML boundary.
  A generated-worker regression reproduces 304 responses for both ETag and
  modification-date requests, for the index and an article in both tenant modes.
  It failed before the fix and passes afterward.
- With the OS set to dark and the web setting explicitly set to Light, generator
  validation used dark-theme pink on a pale background (1.49:1 contrast). The
  fallback media rule did not respect the initialized/manual theme. Validation
  now consumes a theme-owned error token (light contrast 6.18:1), and interactive
  field/search boundaries use a stronger theme-specific border token.
  ThemeService also sets the native `color-scheme` with the chosen app theme so
  checkboxes and native select popups do not retain the opposite OS appearance.

Live evidence and provisional author-style comparisons were captured in the
isolated `festapp-release-smoke-20261025` browser session. The original 17 task
pages were audited in light mode; ordinary text passed the contrast scan, and
interactive validation exposed the reproduced failure. Provisional application
of the corrected stylesheet removed the measured validation failure. These DOM
comparisons are author previews, not evidence that the old production assets
already contained the changes. Final production browser verification follows
the canonical release.

Validation: full webclient suite collected 753 tests: 723 passed, 30 skipped,
zero failures. Targeted help/cache/routing tests: 12 passed. No backend or Flutter
application logic changed in this follow-up.
