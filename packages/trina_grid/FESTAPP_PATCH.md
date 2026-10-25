# Festapp compatibility patch

Upstream release: trina_grid 2.3.0.
Archive: https://pub.dev/api/archives/trina_grid-2.3.0.tar.gz
Archive SHA-256: `94a39418213b2b7c1c4c0229eb78284d41adb8b876756f8832f6a3f4e587cf99`.

The only runtime-package change is the shadcn_ui dependency from ^0.55.0 to
^0.57.3. The breaking generated-localization renames are not referenced by this
grid. Public theme/dropdown/sidebar APIs are checked by analysis and application
grid tests. No grid source or public application contract was changed.

The licensed release sources are included locally. Examples and non-runtime
documentation/test assets may be omitted; package nm retains its protocol tests.
Selection is explicit in root pubspec.yaml dependency_overrides, including clean
checkouts. Local pubspec_overrides.yaml must keep these same canonical overrides.

Remove this copy when a stable upstream release declares these dependencies
compatible, after repeating the affected analysis/tests and native builds.
Do not edit the global pub cache or force unrelated dependency versions.
