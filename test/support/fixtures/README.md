# Client fixture contracts

`main()` registers tests and scoped hooks. Only the standard idempotent Flutter
binding may initialize there. Each fixture is acquired inside a test/setup and
its disposer is registered immediately. `FixtureScope` attempts all cleanup in
reverse acquisition order and reports errors, including after partial setup.

- `SupabaseClientFixture` owns a local client, strict mock transport and fresh
  request log. Auto refresh is disabled; no singleton or persisted session is
  involved. Bank command instances own their pending intents for that client.
- `RootSupabaseFixture` tests the actual application singleton. PKCE/session
  storage is fixture-owned memory. It owns the SDK's subscriptions/client and
  transport until disposal. Auth/rights/information services cache this selected
  client; their root suites remain process-isolated instead of resetting private
  service state. Each suite scopes its own per-test context/logs.
- `LocalAppStorageFixture` exclusively owns path-provider handling and the
  default Sembast connection. It refuses to overwrite another handler, closes
  the database before deleting its directory, and removes only its own handler.
- `RightsContextFixture` owns the public rights/link/router/settings/time context
  of one test and restores it. It does not replace authorization decisions.
- `WidgetEnvironmentFixture` loads real translations through public
  `EasyLocalization` and `Localizations` widgets/delegates. It preloads before
  labels are constructed and waits only for locale readiness, preserving pending
  loads/saves. The Flutter tester owns the root. SDK internals are never imported.
  Czech/default-fallback navigation scenarios use separate processes. A-B-A
  translation contexts are exercised with the other bank/resource fixtures.
- Package-info, secure-storage and localization fixtures that cannot restore an
  initial platform state through public APIs remain isolated. Do not import
  private plugin internals to make incompatible locale/binding suites share an
  engine. Existing localized feature suites retain their scoped setup.

The bank/lifecycle entrypoint verifies local clients, storage and the real bank
composition in A-B-A order. Its two deterministic registration orders are:

```bash
fvm flutter test --no-pub test/components/bank_accounts/bank_adapter_fixture_test.dart
FESTAPP_FIXTURE_ORDER=reverse fvm flutter test --no-pub test/components/bank_accounts/bank_adapter_fixture_test.dart
fvm dart test test_dart/fixtures
```

Default-locale presentation groups share only the standard binding; each case
source retains its own group hooks. They are separate from translated or root
singleton environments. The complete runner includes every fixture contract.

Compatible small default-locale suites use `registerClientSuites` from
`test/support/register_client_suites.dart`. It adds named group scopes and scoped debug log filtering:
setup/teardown and mutable objects remain owned by each source. It does not
install a shared Supabase root, locale reset or service locator. The normal
order and `FESTAPP_FIXTURE_ORDER=reverse` must both pass after changing members.
A source can still be targeted directly with `fvm flutter test --no-pub
path/to/feature_cases.dart`; the complete runner discovers only its aggregate
entrypoint. Auth singletons and non-restorable locale/plugin roots stay isolated.


`LocalizationLogFixture.install` captures the current public printer and restores
it in reverse order. Register `addTearDown(logs.dispose)` immediately in setup.
Strict groups keep every warning/error and capture diagnostics before filtering;
ticket tests still assert no diagnostic was emitted. Only explicitly declared
uninitialized/empty catalog leaf suites suppress expected missing-key output.
The mixed Google locale group stays strict; empty Czech timeline groups declare
their own fallback policy. Every scope reports its debug/missing suppression
counts. A-B-A, nested ownership, failing body/setup cleanup and a missing key
in a real catalog are covered by the lifecycle group. No production logger
configuration or SDK internals are changed.
