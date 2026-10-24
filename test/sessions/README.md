# Shared Flutter test sessions

These entrypoints share a Flutter engine only across suites with compatible
ownership and cleanup. Keep the actual list and classifications in
`automation/client_test_classification.json`; do not duplicate their changing
counts or benchmark timings here.

Each imported cases file registers its `main()` exactly once inside a named
group. Initialization belongs in scoped hooks; controllers, storage, clients,
locale/log fixtures and drafts must be restored or disposed by their owner.
Auth/context singletons and non-restorable plugin/binding state need separate
processes. A helper-only cases import must exclude `main`.

When changing registrations or fixture lifecycles, check normal and
`FESTAPP_FIXTURE_ORDER=reverse` order. Reversal applies at nested session levels,
so both sibling and nested ownership matter. The architecture guard checks
registration and the client runner compares executed origins/skips with the
semantic baseline. Do not reset private SDK internals to make suites shareable.

Use `automation/test_client.sh` for the complete gate. Its worker/RSS policy and
targeted commands live in [Contributing](../../CONTRIBUTING.md#c-client-tests);
fixture responsibilities live in [fixture contracts](../support/fixtures/README.md).
