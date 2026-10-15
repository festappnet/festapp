# Flutter session boundaries

The compiled application can host both complex widget scenarios and simple
contracts when they share a compatible environment. Three default-locale
sessions now reuse that environment across the previous five application
sessions, generic widgets, visual primitives and local auth-session storage.
One actual Czech-catalog session hosts the previous three Czech sessions.
Three more sessions consolidate SDK-backed bank/media/news widgets, the two
legacy-reader command contracts, and Google locale matrices plus key-fallback
timeline contracts. There are 10 discoverable Flutter roots in total.

The actual boundary is ownership, not simply the presence of an SDK or a
translation catalog. SDK widget groups initialize and dispose their own root
client sequentially; bank composition resolves clients by identity. Information
and event command groups capture disjoint services and never use those services
after their own group ends. Auth/rights integration roots remain separate because
they share cached auth/context services. Locale groups load their own catalogs
through public widget roots, so real cs/en and empty fallback catalogs can share
an engine when both registration orders pass. No private reset is used.

Existing named groups remain nested and retain their original setup/teardown.
Their source bodies and assertions are unchanged. Registration reverses at each
shared-session level when FESTAPP_FIXTURE_ORDER=reverse, exercising both sibling
and nested fixture order. Auth/rights root-client contracts remain process-isolated
because those groups share services retaining their client. No application architecture or
SDK internals were modified to enable this consolidation.

The three default sessions were balanced from the previous measured bodies
(about 6.6 / 7.3 / 7.5 worker seconds). The Czech session previously totaled
13.6 worker seconds. These are scheduling inputs, not promised new durations.
Keeping several substantial processes allows two workers to stay busy while
reducing repeated compiler/engine startup. More workers remain outside the
measured 3 GB budget. Generic theme and grid dependency guards still enforce
production boundaries independently of the larger test environments.

Each original cases file keeps its own named group, setup and teardown. Mutable
controllers, storage, clients, widget state and drafts stay local to a case or
its existing fixture. The cash-payment dialog viewport now registers its reset
immediately. No private SDK reset, production test switch or replacement domain
implementation is used. A helper-only cases import must exclude main; the AST
guard still requires the actual main registration exactly once.

Both default and `FESTAPP_FIXTURE_ORDER=reverse` registration orders are checked.
The complete client runner also compares executed names, origins and skips with
the semantic baseline. Individual cases remain directly runnable with FVM.

The architecture guard, Dart and native VM lanes share a light first phase
and complete before the Flutter compiler/engine phase,
so their RSS peaks do not overlap. Failures from all lanes are still collected.
The canonical runner caps default concurrency at two on this host to leave
room under the 3,000,000,000-byte memory budget. Overrides are explicit via
`FESTAPP_CLIENT_CONCURRENCY`; higher concurrency can exceed that budget. The
reported memory is sampled RSS, not an OS-enforced allocation limit.
