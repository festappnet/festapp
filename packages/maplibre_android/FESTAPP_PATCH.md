# Festapp patch for `maplibre_android` 0.3.7

This repository pin preserves high-resolution Flutter style images without
letting `BitmapFactory` interpolate them a second time. The shared platform
interface supplies the image pixel ratio explicitly; Android assigns that
density to the decoded bitmap while keeping its original pixel dimensions.

The Android map state also maps `MapLibreMap.active` to the native
`onStart/onResume` and `onPause/onStop` lifecycle. This keeps cached map
resources in memory without rendering an offstage tab continuously.

The native style-loaded listener is dispatched asynchronously through the Dart
isolate. Upstream 0.3.6 retains the callback strongly, but leaves JNI's
blocking dispatch enabled; on Android this can lose the completion signal and
leave Flutter waiting after the native style has loaded.

Upstream 0.3.7 removes the external ktlint Gradle plugin, resolving the clean
consumer build failure without a local plugin-version pin.

The MapLibre Native Android dependency is pinned to `13.5.1`; do not restore
upstream's dynamic `13.5.+` selector because release artifacts must resolve the
same native renderer on every workstation.

Remove this package and the root `dependency_overrides` entry once upstream
supports an explicit pixel ratio for style images and pausing a retained map.
Validate removal by checking downloaded custom pins and background CPU after
switching away from the map on Android.

## Upstream review: 0.3.7 (2026-10-25)

Rebased this adapter onto the published 0.3.7 archive while retaining the
patches described above. Upstream still lacks the pixel-ratio and retained-map
activity contracts. Android still needs the asynchronous style-loaded callback
and a fixed native renderer version; iOS still needs the public plugin header
and navigation-grade location policy. The dependency overrides remain required.

The upstream released-style guard also covers the local pixel-ratio image path.

The published 0.3.7 JNI bindings contain trailing commas on extension-type
representation fields, rejected by Dart 3.13.2. These commas are removed locally;
regenerating bindings must preserve this parser compatibility.
