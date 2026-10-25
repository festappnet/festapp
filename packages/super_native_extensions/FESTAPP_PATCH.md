# Festapp compatibility patch

Upstream release: super_native_extensions 0.9.1.
Archive: https://pub.dev/api/archives/super_native_extensions-0.9.1.tar.gz
Archive SHA-256: `b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569`.

The only runtime-package change is widening device_info_plus from >=10.0.1
<12.0.0 to >=10.0.1 <14.0.0, matching current upstream. This stable release only
uses DeviceInfoPlugin.deviceInfo and AndroidDeviceInfo.version.sdkInt. Both APIs
are retained by device_info_plus 13.3.0. No Rust/native source or clipboard ABI
was changed. This unlocks win32 6 for current picker/package-info/geolocator.
Keep the release Cargo.lock and cargokit lock. Do not migrate to the prerelease
Rust hooks build system merely to widen a Dart dependency constraint.

The licensed release sources are included locally. Examples and non-runtime
documentation/test assets may be omitted; package nm retains its protocol tests.
Selection is explicit in root pubspec.yaml dependency_overrides, including clean
checkouts. Local pubspec_overrides.yaml must keep these same canonical overrides.

Remove this copy when a stable upstream release declares these dependencies
compatible, after repeating the affected analysis/tests and native builds.
Do not edit the global pub cache or force unrelated dependency versions.
