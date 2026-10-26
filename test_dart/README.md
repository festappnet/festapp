# Dart/VM application contracts

Run `fvm dart test test_dart` from the repository, or use
`automation/test_client.sh` for the complete core + VM + Flutter gate.
These tests import the actual application adapters; core never imports the app.

- Native Sembast storage, offline-map verification and HTTP/atomic file delivery
  exercise actual filesystem/transport boundaries without a Flutter engine.
- Image-control HTTP and image URL composition, structured HTML/contact codecs,
  PWA port metadata, build/source boundaries and public-route normalization are
  application adapters outside the five portable domain modules.
- Auth/profile/logout/password/companion workflows, reload/news badge control,
  organization/icon DTOs and the application search index retain their actual
  application contracts. They do not need Flutter. Mutable speaker/news/icon/
  organization editor DTOs remain application-owned; moving them into core would
  require another ownership migration beyond Event/Product/Form snapshots.
  The search boundary consumes application projections rather than adding a
  reverse app dependency to core.
- The existing loopback-only GoTrue SDK session contract imports the same locked
  `supabase` implementation re-exported by `supabase_flutter`. Its optional local
  fixture and skip are unchanged; no Flutter UI was exercised by that test.
- Fixture cleanup contracts prove reverse cleanup, failure reporting and partial
  setup disposal independently of the Flutter fixture integration checks.

Every migrated case has an explicit origin in the semantic inventory. Flutter
keeps actual renderers, grid/framework adapters, platform plugins and root
singleton integration; their finite classification is in
`automation/client_test_classification.json`.
