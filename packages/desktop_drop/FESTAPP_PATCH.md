# Public native unit-test boundary

Official desktop_drop 0.9.2 archive: https://pub.dev/api/archives/desktop_drop-0.9.2.tar.gz
SHA-256: `1180229beb0342f7da0a407a33ea9dc9f7dafa5917458fe664c169f02ca63b50`.

Runtime Dart/native sources are unchanged. `desktop_drop_testing.dart` exposes
the existing @visibleForTesting native transport through a public library,
so app fixtures do not import SDK-private paths or load unavailable FFI libraries
in a unit-test engine. Browser/native application builds use the real plugin.
Upstream monorepo workspace resolution is removed for standalone use.

Remove this copy when upstream provides a public native testing entrypoint,
and update the fixture import after rerunning its protocol tests.
