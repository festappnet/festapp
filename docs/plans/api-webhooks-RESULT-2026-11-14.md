# API webhook implementation result

Date: 2026-11-14
Status: Feature implemented and verified locally; not published or deployed.

## Implemented

- All eight `webhooks.*` operations in the existing shared operation catalog and
  `/integrations/v1/operations/` API, with explicit read/write scopes, current
  tenant/resource/actor/occasion/form fences and strict output schemas. Outgoing
  order/test payloads have strict allowlists validated before dispatch and formal
  receiver schemas in the operator OpenAPI webhooks section.
- `user_permissions/webhook_operations.sql` owns the typed management predicate.
  Current Make/order-summary ceilings are preserved. Agent-driven mutations have
  destructive hints and explicitly require approval of destination/data scope.
- Canonical SQL outbox, same-transaction recipient fanout, immutable allowlisted
  order/customer/field/ticket snapshot, idempotent management receipts, versioned
  configuration, durable claims and stale-lease fencing. The initial order owner
  emits once; shared offer finalization and receipt replay do not emit again.
- Existing encrypted SQLite stores key-first management intents and signing
  keys; lost responses reconcile the original command/subscription/key. Keys do
  not appear in SQL, logs, list/history responses or plaintext credential files.
- Existing runtime lifecycle starts/stops the bounded dispatcher. Real HTTPS,
  per-attempt DNS validation/pinning, hostname verification, total deadline,
  Standard Webhooks exact-byte signing, overlap rotation, retries, redelivery,
  per-subscription leases and safe attempt history are implemented.
- Order/form/occasion deletion cascades remove snapshots and recipient rows.
  Payload access stops after seven days. A bounded deletion-only job uses the
  existing pg_cron scheduler even after all consents expire. Expired payloads
  and subscriptions no longer occupy the pending-delivery budget indefinitely.
- The first-version 100000-pending-recipient organization cap is checked before
  prospective fanout and fails atomically rather than losing a committed fact.
- An additive forward migration, canonical-source registry/fingerprints, generated
  API/MCP references, six consent translations, developer documentation and a
  runnable signature-verifying, durable, deduplicating receiver are included.

## Verification

34 distinct feature tests passed (retained evidence for unchanged inputs):

| Tests | Evidence |
|---|---|
| Protocol, 15 | CloudEvents identity/time, UTF-8 bounds, independent WebCrypto and Python HMAC vectors, tampering, rotation and retry boundaries |
| Sender, 6 | Real local TLS, hostname/CA verification, DNS pinning, private/mixed/mapped addresses, redirect refusal, 2xx/429/410/503 and DNS/authorization/receiver timeouts |
| Outgoing contracts, 3 | Typed order/test allowlists reject extra disclosures; all eight generated projections expose signed receiver schemas only for operator clients |
| Receiver, 1 | Raw-body/time verification, rejection of tampering, durable SQLite acceptance and delivery/event deduplication |
| Real SQL/API pipeline, 9 | OAuth HTTP management -> anonymous canonical checkout -> committed event -> signed TLS; immutable answers and numeric IDs; secret/command replay; pause/delete; dropped-response reconciliation; live revocation/expiry; concurrent claims/registration; rollback/commit visibility; attempt/deadline limits; restart after acceptance before completion; retention; 100000-row atomic backpressure |

Commands and additional checks:

- `pnpm exec node --test --test-reporter=dot test/webhook-protocol.test.mjs`:
  15 passed (foundation receipt).
- `pnpm exec node --test --test-reporter=spec test/webhook-delivery.test.mjs`:
  6 passed; actual local TLS network, not simulated fetch acceptance.
- The broader existing runtime/API/storage/policy/connection/MCP batch, including
  `test/webhook-receiver.test.mjs`: 156 passed, no skips.
- `FESTAPP_MCP_TEST_DATABASE_URL=... pnpm exec node --test --test-reporter=spec --test-concurrency=1 test/webhooks-postgres.test.mjs`:
  8 passed, no skips. Final retention-only rerun passed after the retention cleanup
  refinement. A fresh baseline/forward bootstrap and full eight-case rerun also
  passed after strict outgoing payload validation was wired in. The load fixture
  plus atomic-rejection proof took about 2.5 seconds.
- Existing `forms-completion-postgres.test.mjs`: all 11 cases passed, including
  canonical checkout replay, invoice recovery, waitlist and cash administration.
- `pnpm run api:check`: schemas, parity, examples, lint and deterministic offline
  docs passed for all eight facade/data/proof projections.
- `pnpm run docs:check`: current 201 tools / 85 permissions reference.
- `python3 automation/assemble-integration-webhooks-migration.py --check` and
  `python3 automation/generate_canonical_source_contract.py --check`: passed.
- Real `canonical_mutation_source_parity_test.sql`: exactly one file selected,
  passed against the migrated disposable database (final run about 107 ms).
- Canonical operation-owner checks after follow-up: all ten passed, including
  sole owner, immutable forward registration, trusted SECURITY DEFINER search
  paths and generated-contract reproducibility.
- Final API-only contract/transport/docs batch: 31 passed, zero failed, no skips.
  This clean batch is independent of the separate pre-existing owner-test failure.

The database was bootstrapped from the repository's baseline/forward workflow
into task-owned `festapp-webhooks-20261114` on loopback port 61932. All application
email capacities were paused, outbound worker URLs absent and cron execution off.
Its canonical-source parity test proves the final SQL definitions match release
inputs. Test TLS listeners and encrypted temporary stores were closed. The
task-owned database project was stopped with `--no-backup` at completion; no
background service from this task remains running.
No production access, real email delivery, paid endpoint, Flutter or browser was
used. Tests ran with pnpm 11.24.0 and workstation Node 26.8.1; oidc-provider warns
that its supported production runtime should be an LTS Node release.

## Resolved blockers and publication conditions

1. **Resolved: order decoding.** The strict operator payment schema now accepts
   the existing SQL-owned `net` and `pending` decimal strings, matching the public
   summary projection's established optional fields. Unknown fields remain
   rejected. The original real PostgreSQL order read/edit/payment/queue/replay
   test now passes and explicitly checks both decoded totals. Its fixture also
   now sets the organizer's required bank/cash policy instead of depending on a
   removed implicit default; no production payment guard was weakened.
2. **Resolved: stale editor contract.** Regenerated the ticket-layout readiness
   attestation from its current canonical source list and included it in additive
   forward `20261114130000_ticket_layout_contract_refresh.sql`. Existing migration
   bytes were preserved. Five real SQL test files (settings, reads, authoring,
   legacy fences and canonical source parity) pass. The real MCP PostgreSQL
   preview/save/replay/conflict test also passes, proving readiness works and
   still rejects intentional body/privilege drift.
3. `contracts/api-v1/release-baseline.json` is `unreleased`, with no contracts.
   Compatibility against a published baseline cannot yet be certified; schema
   compatibility unit tests do pass. Do not invent a released baseline.
4. The pre-existing checkout is a broadly dirty
   `docs/festapp-tickets-readme-20261107` branch. No commit/push/merge was performed.
   A future publication must reconcile this feature with canonical main and run
   the required affected CI mirror/GitHub gates before release.
5. Subscription expiry freezes the original connection deadline, capped by the
   original consent and its current idle deadline. Refresh does not extend a
   subscription; the caller must replace it explicitly before reported expiry.
   Reconnection does not inherit old endpoints. Already sent data cannot be
   recalled, and ordering/exactly-once effects are not promised.

## Follow-up verification (both previously reported defects resolved)

- Original `test/orders-postgres.test.mjs`: 1 passed, zero skipped.
- `automation/tests/canonical_operation_sources.test.mjs`: all 10 passed.
- Current API contract/transport/docs/readiness batch: 35 passed, zero skipped.
- `pnpm run api:check`: all eight schema/example/lint/offline-doc projections pass.
- Real SQL selection `ticket_layout_ canonical_mutation_source_parity_test.sql`:
  exactly 5 files selected, 5 passed, 0 failed.
- `test/layout-postgres.test.mjs`: real authenticated MCP preview/save/replay/
  conflict case passed against the migrated task-owned database.
- Existing webhook PostgreSQL pipeline cases: all 8 passed after the operator
  decoder/forward migration change; the isolated original order test then passed
  after its payment-policy fixture was updated.
- The forward migration and canonical source/attestation generators check clean.
  API/MCP schemas and offline references were regenerated from final source.

## Bounded efficiency follow-up

The isolated warm producer measured about 0.174 ms for one matching recipient
and 0.781 ms with a 10000-delivery backlog. A proposed SQL routing consolidation
showed no measurable benefit and was reverted. The earlier approximately 2 ms
whole-checkout difference must not be interpreted as isolated producer cost;
ordinary run-to-run variation also contributes. No total CPU claim is made.

The adopted change removes redundant per-poll retention work: an idle active
endpoint now issues one claim RPC instead of purge plus claim. In the paired
10000-backlog experiment, SQL polling fell from 1.129 ms to 0.233 ms (about 79%
less time for that SQL pair/poll, excluding upstream Auth). Paused, disabled and
expired endpoints do not poll or refresh backend credentials. Pending management
intents still reconcile. Poll cadence and pre-send authorization remain unchanged.

Retention has one scheduled owner, the existing cron job. The obsolete scoped
purge RPC branch was removed. The rejected SQL copies and temporary comparison
harness were deleted; only the existing reusable benchmark and measurement JSON
remain. See `docs/operations/benchmarks/webhooks-efficiency-2026-11-14.json`.

All nine real SQL/API/TLS pipeline cases pass, including a new regression proving
one RPC per idle active poll and zero backend calls for paused/expired endpoints.
No new service, process, broker, dependencies, participant model or key store was
introduced by this optimization. Payloads remain shared across recipients and
bounded by the existing retention and queue limits.

## Deployment boundary

Local implementation is complete. Production migration, client-policy activation,
source publication and rollout were not requested in this execution. Apply the
canonical additive migration before the updated existing integration runtime,
then explicitly enable the operator client/scopes and obtain consent. Preserve
selected-tenant scope and production backend/release safeguards. Stop dispatch
and retain queue/keys/receipts for rollback; do not discard undelivered facts.

Developer usage: [tools/festapp/WEBHOOKS.md](../../tools/festapp/WEBHOOKS.md).
Authoritative architecture: [api-webhooks-plan-2026-11-14.md](api-webhooks-plan-2026-11-14.md).
