Upstream: irondash_engine_context 0.5.5 from pub.dev (https://github.com/irondash/irondash).

Native and Dart runtime sources are unchanged. The Android build uses the existing identical CargoKit implementation in ../super_native_extensions/cargokit rather than a second copy. The shared Gradle task uses injected ExecOperations for Gradle 9.

The Android compile SDK follows the Flutter-provided compileSdkVersion.
