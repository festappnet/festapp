# Festapp compatibility patch

Upstream release: super_native_extensions 0.9.1.
Archive: https://pub.dev/api/archives/super_native_extensions-0.9.1.tar.gz
Archive SHA-256: `b9611dcb68f1047d6f3ef11af25e4e68a21b1a705bbcc3eb8cb4e9f5c3148569`.

The Dart compatibility change widens device_info_plus from >=10.0.1
<12.0.0 to >=10.0.1 <14.0.0, matching current upstream. This stable release only
uses DeviceInfoPlugin.deviceInfo and AndroidDeviceInfo.version.sdkInt. Both APIs
are retained by device_info_plus 13.3.0. This Dart change did not modify Rust/native source or the clipboard ABI. This unlocks win32 6 for current picker/package-info/geolocator.
Keep the release Cargo.lock and cargokit lock. Do not migrate to the prerelease
Rust hooks build system merely to widen a Dart dependency constraint.

The licensed release sources are included locally. Examples and non-runtime
documentation/test assets may be omitted; package nm retains its protocol tests.
Selection is explicit in root pubspec.yaml dependency_overrides, including clean
checkouts. Local pubspec_overrides.yaml must keep these same canonical overrides.

Remove this copy when a stable upstream release declares these dependencies
compatible, after repeating the affected analysis/tests and native builds.
Do not edit the global pub cache or force unrelated dependency versions.

## Native dependency security

`simple_logger` 5.2 removes its dependency on vulnerable, unmaintained `atty`
(RUSTSEC-2021-0145). The existing `init_with_level` caller remains compatible.

GTK 0.17 requires GLib 0.17; upgrading GLib alone to 0.20 would mix incompatible
binding types. The Cargo patch pins Festapp's GLib 0.17 security backport at
`5893f66e6385c2235982db0b2482aa86b46ea097`. It applies the upstream two-line
`VariantStrIter::impl_get` mutable-out-pointer fix for RUSTSEC-2024-0429, without
changing crate versions or the GTK ABI. The fork normalizes GLib's internal
manifest paths to consume the same registry sys/macro dependencies.

Source and provenance:
https://github.com/festappnet/gtk-rs-core/blob/5893f66e6385c2235982db0b2482aa86b46ea097/SECURITY-BACKPORT.md

`automation/native-security` checks that both locked graphs use that same Git
revision, excludes `atty`, and exercises all five affected string-iterator
operations in an optimized executable. The unpatched GLib 0.17.10 probe crashed
with exit 139; the backport passes. The native security workflow also compiles
the real plugin's Linux graph with `cargo check --locked`.
