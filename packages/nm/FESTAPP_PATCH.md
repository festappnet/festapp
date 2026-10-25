# Festapp compatibility patch

Upstream release: nm 0.6.0.
Archive: https://pub.dev/api/archives/nm-0.6.0.tar.gz
Archive SHA-256: `2ae480aa3379716b8bb58dfebb168e2919394c92b629efaaa0baaa5d140786e6`.

The only runtime-package change is widening dbus ^0.8.0 to >=0.7.10 <0.9.0.
The 0.8 breaking change affects generated multiple-return-value code, not this
handwritten NetworkManager client. The client retains the DBus 0.7 APIs.
This lets connectivity_plus 7.3.2 coexist with the current official Linux
geolocator/geoclue/gsettings plugins that still require DBus 0.7.
The upstream NetworkManager test suite is retained to verify this compatibility
against an actual local DBus server on Linux, not a production network service.

The licensed release sources are included locally. Examples and non-runtime
documentation/test assets may be omitted; package nm retains its protocol tests.
Selection is explicit in root pubspec.yaml dependency_overrides, including clean
checkouts. Local pubspec_overrides.yaml must keep these same canonical overrides.

Remove this copy when a stable upstream release declares these dependencies
compatible, after repeating the affected analysis/tests and native builds.
Do not edit the global pub cache or force unrelated dependency versions.
