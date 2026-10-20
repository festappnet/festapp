# Command recovery unification, 2026-10-20

Normal command dispatch and explicit recovery previously decided whether to retire a durable intent using duplicate loose checks over raw response maps. A response with code 200 and a matching command ID could remove recovery state even when required receipt fields were missing. The typed domain adapter would then reject the malformed response after the intent had already disappeared.

`ClientCommandTransport` now owns one confirmation path for both dispatch and recovery. It validates a terminal candidate through the existing `festapp_core` command-response parser, checks the exact command ID, and only then invokes the existing atomic principal/ID compare-and-clear. Invalid replies retain the original intent. Expired tombstones remain non-replayable recovery state and cannot silently allocate a new command ID.

The warm in-memory adapter uses that same receipt decoder and ID check. Durable and in-memory storage remain distinct lifecycle mechanisms inside the same transport; this change does not replace payment/Edge workflow contracts or change domain permissions. The caller receives the original response shape.

`ClientCommandIdentity` now has one builder for persisted pending keys and one for active scope keys, both using its existing canonical fingerprint. Their byte formats remain unchanged. A historical-record fixture verifies recovery after reopening, map-key order independence, exact cleanup and preservation of an unrelated unresolved payment intent. No pending-store migration or payment reset is introduced.

A protocol-shaped fixture is shared by the transport tests. Malformed cases remove the specific field under test, so a success fixture can no longer accidentally omit mandatory receipt fields. Tests cover malformed responses on both dispatch and resume, exact replay, actor changes during dispatch, independent resource scopes, unchanged/rejected/conflict confirmation, expired receipts, and original editor baselines. Group creation reconciliation, activity time/draft handling, form and product command adapters remain covered.

Validation: 31 targeted Flutter tests passed with concurrency 1 in one temporary batch harness. The harness was removed after verification; the cases remain registered in their existing repository discovery roots. Logs: `/tmp/festapp-architecture-flutter.log`. Source/SQL follow-up logs are `/tmp/festapp-architecture-source-wave2.log`, `/tmp/festapp-architecture-sql-wave2.log` and `/tmp/festapp-architecture-concurrency-wave2.log`.

These changes and the five-identity SQL cleanup are local, not production-applied. MCP remains deferred and Blueprint V2 is excluded. The established backend domain owners, PDF renderer, receipts and notification queue remain authoritative for the future connector.

## Edge waitlist identity follow-up

The Flutter waitlist adapter owned an in-memory UUID but invoked the shared transport without passing it. The Edge request consequently used one UUID while the transport checked the response against a second UUID. Both registration commands and offer acceptance now pass their pending identity explicitly, and the Edge adapter maps the transport-bound ID into the HTTP body. This retains one identity through SQL receipts, response validation and retries.

Pending keys now use the existing canonical fingerprint and include the current actor. Nested request data is snapshotted before asynchronous dispatch. Capabilities and payloads remain in memory; no durable intent is claimed. Domain 408/429 and server failures retain the identity, while confirmed terminal outcomes retire it. The Supabase SDK wraps network failures in `FunctionsFetchException`; the Edge adapter unwraps only the timeout/client-error types already covered by the shared retry policy. Other SDK/domain errors retain their existing behavior.

The shared transport now also checks the captured actor before every attempt. An account change following an ambiguous network failure stops redispatch before sending the previous actor's intent with a new session.

Verification: 21 targeted Flutter tests passed in one engine with concurrency 1, including seven new tests through a real Supabase client's mocked HTTP boundary and a transport regression for actor changes between attempts. Log: `/tmp/festapp-waitlist-architecture-test.log`. The new waitlist cases are registered in the existing forms suite and its source classification. This is local verification, not a live Edge/provider or production release check.

The repository architecture guard also passed (`/tmp/festapp-waitlist-architecture-guard.log`). Its first execution required resolving the core package's local dependencies; the subsequent check exposed six existing setup/invitation test roots without classifications. Concrete widget/adapter classifications now cover those roots. This repairs registration metadata; it does not claim those six suites were executed in this follow-up. No dependency lockfile changed.

Subsequent authorization and implementation: [local MCP E0](mcp-e0-local-execution-2026-10-20.md). Statements above about deferred MCP describe this earlier cleanup checkpoint.
