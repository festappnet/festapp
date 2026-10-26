# Flutter web startup - implementation 2026-10-14

Implemented locally from the [measured proposal](flutter-web-startup-measurement-2026-10-14.md). No deployment, version change, branch propagation or publication was performed.

## Changes

- `FormFontCatalog` is the single deferred import of `google_fonts`. Successful loading is shared, and failures allow another attempt. Forms without a custom font do not request this catalog. Custom-font forms wait for it and offer retry on a failed download; unsupported font families retain the existing theme fallback.
- Form design keeps color controls usable while its font picker loads. Failed catalog loading offers retry without changing the selected font or calling the parent's change callback. The error text exists in all six bundled languages.
- The canonical shared web build removes automatic registration for six unused Lucide weights and the unused golden_toolkit font. It checks the main executable and every deferred part before removing a registration. Referenced weights stay registered. All physical font assets and AssetManifest entries remain available; native builds are unaffected.
- The existing PWA worker continues precaching every executable part atomically. Route splitting remains disabled. The stale npm-command source regex in the existing offline test now accepts the actual split install/build commands.

## Final compiled artifact

Flutter 3.47.2, release JavaScript build of the current working copy; identical compression settings to the earlier baseline.

| Artifact | Raw bytes | Gzip level 9 | Brotli quality 9 |
|---|---:|---:|---:|
| Main | 11,191,958 | 3,038,248 | 2,537,204 |
| Deferred catalog | 10,111,259 | 730,002 | 543,430 |
| Fonts no longer automatically requested | 2,718,732 | 1,268,718 | 1,105,688 |

The baseline main was 21,329,870 raw / 3,776,596 gzip / 3,093,298 Brotli bytes. Combined savings in the initial main and automatic font requests are approximately 2.01 MB gzip / 1.66 MB Brotli. These are artifact measurements, not a measured improvement in authenticated administration startup seconds. PWA installation still downloads the deferred code in the background.

Seven font families remain registered, covering nine files instead of sixteen. Futura, Material Icons, regular Lucide, Geist/GeistMono, Cupertino Icons and the Flutter fallback Roboto are preserved.

## Verification

- Targeted Flutter widget tests: 5 passed, including failed catalog download, preserved selection, retry and subsequent successful font selection.
- Node tests for font optimization and PWA manifest/reconciliation: 6 passed. The font tests also prove that references confined to a deferred part retain their family and that missing compiled input cannot mutate the font manifest.
- Full existing `pwa_offline.test.mjs`: passed.
- Actual build artifact check: main and the one produced deferred part both belong to the atomic PWA core cache.
- Release build: passed (47.4 s compilation).
- Targeted analyzer: no errors; existing files report 1 warning and 27 informational diagnostics. None are on added or modified lines. New catalog and test have no diagnostics. The analyzer command therefore returns nonzero and is not reported as a clean analyzer pass.
- Whitespace checks: passed for the touched implementation paths.

Earlier isolated Chromium tests using a genuinely deferred Dart program and this repository's worker verified first-use offline loading and coexistence of old/new tabs after update. This implementation has not been deployed or tested as a full authenticated production administration session, nor as an iOS standalone PWA. A release should still smoke-test those journeys, including unavailable storage and recovery without discarding drafts.

Machine-readable artifact measurements: [implementation-result.json](flutter-web-startup-evidence-2026-10-14/implementation-result.json), [implementation-pwa-artifact.json](flutter-web-startup-evidence-2026-10-14/implementation-pwa-artifact.json).
