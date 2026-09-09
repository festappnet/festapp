# Festapp patch for `maplibre_android` 0.3.6

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

The embedded Android build pins its external ktlint Gradle plugin because
Flutter evaluates this vendored module inside the application build, outside
the upstream repository's plugin-version management.

The MapLibre Native Android dependency is pinned to `13.5.1`; do not restore
upstream's dynamic `13.5.+` selector because release artifacts must resolve the
same native renderer on every workstation.

Remove this package and the root `dependency_overrides` entry once upstream
supports an explicit pixel ratio for style images and pausing a retained map.
Validate removal by checking downloaded custom pins and background CPU after
switching away from the map on Android.
