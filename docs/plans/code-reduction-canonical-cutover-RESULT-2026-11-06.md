# Code reduction / canonical cutover - local execution result

Implemented locally on 2026-11-06 in `/Users/miakh/source/festapp-code-reduction-20261106`.
Base `92ee5c61165cb214b2164ab424b46ef82d5047b1`; the original dirty checkout was not changed.
The user explicitly included the source of PR #733 (`0185c3a68`), #734 (`4334fc5d7`)
and #736 (`d9ec85229`). Their diffs were integrated locally, without commits or a
GitHub merge. The package/lock overlap merged cleanly and frozen pnpm install passed.

## Result and ownership

- One benchmark, sustained and maintenance command set replaces both generations.
  `benchmark_support.mjs` owns disposable guards, connections, recorded fixtures,
  claim restoration, cleanup and timings. Output is checked before fixture writes;
  sustained work uses separate connections and retains an incomplete receipt before
  throwing. Old prepared-prefixed entrypoints and delivery-only/daily variants are gone.
- `OrderContactController` owns confirmed snapshot, draft, busy/stale, command outcome,
  pending intent, recovery and readback for detail and standalone dialog. Detail global
  save calls the same owner without sending and cannot bypass pending uncertainty.
  Confirmed contact remains clean after failed readback. Inline saves still advance
  their full-array fences individually. Identity changes discard late reads.
- `TicketFontCatalog.loadSetupFonts()` projects the small bundled policy and existing
  immutable catalog. All 1,892 ordered family/ID pairs matched the removed Dart map.
  The immutable map shares in-flight loading and retries failed assets/catalog reads.
  Copied custom layout/font identity survives; the SQL projection is byte-for-byte unchanged.
- Prepared views are the only admin-center serving API. Token-bound order selection
  uses captured prepared membership, full sequence envelopes and current authority;
  successful orders responses call the canonical view read owner. Shared DTO,
  classification and receipt batching now live in `notification_center/shared.sql`.
- The new forward migration explicitly removes 12 public RPC names and four private
  presentation helpers. Four obsolete SQL files are deleted. Source manifests, ACL and
  definer inventories, prerequisite guard and generated source parity were updated.
  No CASCADE, application trigger, data deletion or migration-history rewrite was used.

The user's Slunovrat exception means Android/iPhone news push delivery, **not** the
editor/admin center. News, mobile notification helper and `supabase/functions/notify`
are unchanged. This clarification authorizes local admin-center contraction; it does
not authorize production rollout or tenant propagation.

## Reduction

Physical text-line changes against the base **plus all three PR diffs**, excluding
those PRs' own changes and excluding execution evidence from runtime counts:

| Category | Net lines |
|---|---:|
| Handwritten runtime sources, including new owners/helpers | -388 |
| Generated Dart catalog projection | -3,787 |
| Generated forward migration | +513 |
| Config/contracts, including explicit definer ACL inventory | +459 |
| Tests/fixtures, including replacement coverage | -86 |
| Generated source-parity test | -18 |

These are not executable LOC, bundle-size or performance claims. Detailed file
counts, source identities, digests and check receipts are in the sibling JSON.
Historical objects, hashes, offline readers, applied migrations and font SQL are retained.

## Verification

- Fresh install and real upgrade from the immediate predecessor produced identical
  function bodies/grants/owners, columns, indexes and constraints. All 16 retired
  signatures are absent. The upgrade used only the new migration on loopback.
- Canonical notification SQL plus source parity: **34 passed**. Genuine database
  concurrency: **14 passed**, including prepared open/read/sequence and lease contention.
- Assembler/protocol: **6 passed**, including executing the real prerequisite guard
  with a missing canonical scope owner. Benchmark guard/lifecycle tests: **5 passed**.
  CI command contract: **6 passed**. Generator/source/whitespace checks passed.
- Targeted Flutter suites cover save without resend, confirmed commit with failed
  readback, 409, original pending UUID after reopening/discard, occasion change,
  retained widget identity, source-copy preservation and offline font retries/parity.
  Latest contact widget batch: **30 passed**, additional rebind suite: **2 passed**;
  final global-save suite: **7 passed**. Targeted analyzers have no errors/warnings;
  existing style infos remain.
- Real disposable scenarios: 3-event benchmark, 1,000-event/5-recipient maintenance,
  2,400-event/12,000-delivery sustained workload with zero pending recipients. The
  maintenance assertions now match hidden-order visibility and compacted read history.

Six tests exclusive to retired feed/calendar/group serialization were removed.
Their surviving snapshot/ACL, late-arrival, count/privacy, receipt-gap/self/inherited,
reverse-read, quota and paging invariants are covered by the prepared orders,
history, scope-authority, wide-scope, lifecycle, retention and concurrency suites.
Mixed producer/policy tests were migrated to actual canonical responses; their
bounded readiness helper lives only in `pg_temp` and does not translate old DTOs.

## Remaining gates and operations

The initial handoff reported incomplete test classification, one private SDK
fixture import and missing definer metadata. The authorized blocker follow-up
resolved them without weakening the guards or changing application SQL/grants:

- All 23 existing Flutter roots now have concrete engine/environment reasons.
  The architecture guard passes on the final source.
- The viewer regression uses public `VenueLayoutViewer` and the existing shared
  canvas fixture. All 11 viewer cases pass; its analyzer reports no issues.
- The inventory declares 43 exact current definer headers and their real ACLs.
  All 129 role checks match the disposable database; the existing provider
  `service_role` default remains intact. All 8 security contract checks pass.
- The other 22 registered roots pass 188 tests; their two app-mode skips are
  exercised by the ticketing-only run, where all 3 tests pass. The CI command
  contract passes 6 tests. Viewer/security checks are wired into the canonical
  navigation/seat-notification mirror command lists.

The blocker follow-up deletes no additional tests: these regressions still cover
supported behavior. Shared fixture reuse removes the private SDK coupling and
repeated painter lookup. Full mirror lanes remain a normal prerequisite before
any later source publication; no full-CI or release attestation is claimed here.

At the implementation handoff, no commit, push, PR merge, production SQL,
deployment, minimum-client-version change or tenant propagation had been performed.
The subsequent user instruction authorizes one consolidated squash publication
and deployment to `prod/festapptickets` only; release evidence is recorded separately. Production still requires a separately authorized
release with exact source/tenant selection and normal production gates. No legacy
admin-center compatibility adapter remains in the local canonical implementation.
