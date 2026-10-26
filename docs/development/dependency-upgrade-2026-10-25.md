# Dependency upgrade - 2026-10-25

Local changes and verification only. No deployment, publication or production
storage/database migration was performed.

## Current result

Stable Flutter 3.47.7 / Dart 3.13.5 is selected in FVM and canonical
`automation/project.conf`. Other tenant configurations were not changed.

- cross_file 0.4.0 and desktop_drop 0.9.2 are now implemented, including the
  application import boundary and seven coordinated latest picker packages.
- file_picker 13.2.0, flutter_secure_storage 11.2.0, geolocator 14.1.2,
  package_info_plus 10.2.2, connectivity_plus 7.3.2 and shadcn_ui 0.57.3.
- timezone 0.11.2, CSV 8.0.0, file_saver 0.7.0 and build_runner 2.16.1.
- Earlier UI/AutoRoute upgrades and MapLibre 0.3.7 remain. The latest MapLibre
  release does not replace all Festapp patches; retain `packages/maplibre_*/FESTAPP_PATCH.md`.
- Web Vite 8.3.5 keeps the previous Chrome/Edge 107, Firefox 104, Safari 16
  baseline. dotenv 18.0.9, p-limit 7.3.3, worker TypeScript 7.0.2,
  Vitest 5.0.5 and jose 6.2.13 are verified in the earlier receipts.

## File compatibility and retention

The old picker ecosystem still used cross_file 0.3 constructors and accessors.
A version override alone would not compile. The coordinated release-source port
is documented, with exact archive checksums and removal gates, in
[`packages/file_picker/FESTAPP_PATCH.md`](../../packages/file_picker/FESTAPP_PATCH.md).
Its shared provider adapter preserves names, cached bytes, UTF-8 decoding,
filesystem URI encoding and independent range streams. Native picker platform
code is unchanged. Root tracked overrides and relative package links select all
seven copies, including standalone browser tests from a clean checkout.

The application passes `ImportFile` values with stable metadata and explicit
content retention. Uploads await their lazy provider reads inside onDrop. Dialogs retain content before returning it, including a
confirmation that happens while bytes are still arriving. Metadata and retained
length remain usable after the provider expires. Image size checks happen before
content reads; ordinary uploads are not eagerly buffered ahead of these checks.
Imports explicitly use copy, never move; errors stay errors instead of empty
successful files. No persisted file paths or application records are rewritten.

## Login bug fixed

`AuthService.login` was missing the sign-in-code exchange entirely. It sent six
digits directly as a password, explaining both old test failures.

Exactly six digits now call the existing `exchange-sign-in-code` function with
the unprefixed mailbox (including its plus tag), organization and unchanged code.
A returned refresh token uses Auth session refresh and the existing login
finalization. An empty proof permits the original tenant-prefixed password
fallback. Exchange errors propagate without an ambiguous password attempt.
Ordinary passwords keep their direct Auth path. Server-side code expiry and
consumption logic was not changed. All four request-level regression cases pass.

## Canonical time contract preserved

`OccasionTimeContext` in the leaf `festapp_core/time.dart` module (also exported
by `program.dart`) owns full embedded timezone initialization,
selection fallback, named/current contexts, instant/wall conversion and DST price
candidates. `TimeHelper` delegates to it; the three old platform adapters are gone.

Preserved: saved IANA aliases and settings JSON metadata, Prague fallback, UTC
instants versus wall times, subsecond precision, time travel, the existing 04:00
program boundary and overnight grouping, DST gaps/overlaps, device-calendar
notification labels and intentional Prague SQL report buckets. JavaScript keeps
its existing browser-local Intl presentation. These policies are not conflated.
The full dataset retains saved names omitted from the reduced 0.11 dataset.
Current IANA rules can legitimately update civil offsets where regional rules
changed; stored instants and saved zone selections are not renamed or rewritten.

## Other reviewed compatibility patches

- Stable super_native_extensions 0.9.1 accepts device_info_plus 13, matching
  current upstream. Rust/native source is unchanged. This unblocks win32 6.
- TrinaGrid 2.3.0 accepts shadcn_ui 0.57.3; its source does not use the renamed
  generated localization classes.
- desktop_drop 0.9.2 exposes its existing native test transport through a public
  `desktop_drop_testing.dart` entrypoint. Runtime/native sources are unchanged;
  the application fixture no longer imports package internals.
- nm 0.6.0 permits DBus 0.7.10-0.8.x. All 56 upstream protocol tests passed with
  DBus 0.7.15 in a disposable Linux container and a real local DBus server.
  The current Linux geolocator ecosystem still needs DBus 0.7.

Each copy has its own `FESTAPP_PATCH.md`. No global pub-cache source was edited.
Apple secure-storage service/accessibility options and the `refresh` key remain
unchanged. flutter_secure_storage v11 requires v10 migration before an upgrade
from older Android cipher formats; the prior repository dependency was 10.3.4.
No direct upgrade from a pre-v10 deployed Android build is claimed as tested.

## Remaining version gaps

| Package now | Latest | Concrete stable-SDK constraint |
| --- | --- | --- |
| build_runner 2.16.1 | 2.17.1 | New analyzer 14.3 conflicts with SDK-compatible test 1.31.1, which requires analyzer below 14. |
| test 1.31.1 | 1.33.0 | Stable Flutter 3.47.7 pins test_api 0.7.12; latest test needs 0.7.15. |

Do not force Flutter's test_api pin. The shared venue editor migration remains
local in `/Users/miakh/source/venue_seat_picker`, selected by the existing ignored
override. Publishing that editor and updating the production git pin is still
required for a release reproducible from a clean checkout.

## Older failures resolved

Production fixes include typed draft-map normalization, narrow price-wave labels,
a reactive unsaved-changes route guard after resizing a blueprint, a horizontal
shared color palette, intrinsic-safe appearance presets, canvas-clamped pasted
assemblies and readable white labels on Cinema red seats. The original login
failures are covered by the four HTTP exchange tests described above.

Outdated test fixtures now use the actual shared palette, current controls and
translations, a real form session, a primary mouse button and explicit scrolling
to offscreen controls. Toast tests wait for the actual notification lifetime.
Nine historical inventory mismatches have explicit contract revisions; scanner
configuration and image processing follow their current canonical owners. All
four background-image scenarios remain executed against the actual upload
boundary. The removed legacy-cohort success assertion is already covered by an
existing canonical command case and is counted once. A real missing-RPC failure
still verifies that no alternate mutation runs. The restored resize/discard test
found and verifies the reactive route-guard fix above.

## Verification and limits

Current receipts: `/tmp/festapp-clean-2026-10-25/`.

- Complete canonical client runner passes, with concurrency 1: 1,291 Flutter
  cases, 188 core cases and 78 adapter cases passed; one existing adapter case
  remains skipped. Architecture and semantic inventory guards pass: 1,233
  baseline cases accounted for and 325 added cases, with 43 explicit contract
  revisions. No failures are suppressed.
- Full shared-editor suite: 214 UI and 289 core cases passed.
- Full web suite: 483 passed, 23 existing skips, zero failures.
- Image-worker unit suite: all 95 cases passed, including server-owned image
  profiles, scale-down and PNG-alpha handling.
- Targeted analysis of changed application sources, time API and boundary tests:
  no issues found. This is not a claim about repository-wide lint diagnostics.
- Core and application regression coverage includes preserved timezone settings,
  aliases, midnight/program-day boundaries and DST scheduling. The time module
  extraction changes ownership, with its previous program API re-exported.
- Previous file-import verification remains applicable to unchanged runtime
  sources: 33 browser picker/Blob contracts and 16 real DOM drag/drop
  cases in isolated headless Chrome, plus native provider/retention contracts.
  Earlier receipts remain under `/tmp/festapp-crossfile-auth/`.
- The native Flutter test engine lacks linked plugin FFI symbols. Its explicit
  test-only transport fixture exercises the actual plugin coordinator and source
  reader; browser and application builds use the real plugin.

Android application inspection/builds are excluded by the standing restriction
for `fstapp.fstapp` in
[festapp-google-play-release](/Users/miakh/.codex/skills/festapp-google-play-release/SKILL.md):
"This includes read-only inspection, inventory/preflight API calls, protected
request provisioning, builds, uploads, releases and retries."
No Android application verification is claimed. Native picker platform code is
unchanged, but OS dialogs on physical devices are not covered by mock unit tests.

Final builds of the frozen cleanup sources passed on Flutter 3.47.7: web release
in 58.01 seconds and unsigned iOS archive in 90.30 seconds. The full timezone
asset is present and all five native transport symbols (`dd_rpc_open`,
`dd_rpc_call`, `dd_rpc_complete`, `dd_alloc`, `dd_free`) are exported. Source
fingerprints match before and after both builds. No Android build was run.
Receipts: `/tmp/festapp-clean-2026-10-25/builds/build-results.json`.
