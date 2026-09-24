# Execute to completion: canonical offline sync and application mutations

Work in `<repo-root>`. Obey `AGENTS.md`,
`docs/architecture/ai_context.md`, repository migration rules, and the current
verification mode. This is an implementation and canonical-cutover task, not a
planning or review-only task.

The authoritative plan is:

`docs/plans/offline-sync-revision-cache-plan-2026-08-02.md`

Read it in full before editing. Also read and obey:

- `docs/architecture/mutations.md`;
- `docs/plans/offline-sync-preflight-baseline-2026-08-02.md`;
- `docs/architecture/database.md`;
- `docs/architecture/SERVICES.md`;
- `docs/backend/edge_functions.md`;
- `CONTRIBUTING.md`.

The plan was mutation-hardened on 2026-08-03. If current repository evidence
invalidates a factual premise, update the authoritative plan and this prompt
before diverging. Do not silently substitute a different architecture.

## Required outcome

Finish Waves 0–6 in repository code and leave Festapp with one canonical sync
read path and one canonical mutation path for every in-scope user intent:

- Supabase PostgreSQL remains the source of truth for writes, authorization,
  exact capacity/stock decisions, mutation receipts, audit commits, component
  heads and private payloads.
- Public structural catalogs and `live_public` are immutable,
  content-addressed R2 artifacts referenced by one verified public head.
- Private overlays come only from the authorized read-only Supabase handshake.
- One `ClientSyncService` owns local generations, activation, lifecycle,
  navigation refresh, polling, single-flight, backoff and freshness state.
- Every user intent persists through one explicitly named domain RPC and one
  PostgreSQL transaction, or through the explicitly allowed
  Edge → service-only DB command/outbox → worker lane for external effects.
- Every migrated consumer reads its active local projection. No feature page
  owns a second loader, timer, fallback or reference side-fetch.
- Every real sync-relevant state change creates exactly one redacted audit
  commit and all resulting revisions in the same transaction.
- Every completed command has an idempotency receipt, including unchanged,
  rejected and conflict outcomes; those non-changing outcomes create no commit
  and no revision bump.
- `Admin → Změny` is permission-gated, online-only and backed by the commit
  ledger, not by a replay/event-sourcing model.

Do not stop after scaffolding, a reference slice, compilation, or a partially
migrated feature. Continue until the Definition of Complete and deletion ledger
in the plan are satisfied, or until an action genuinely requires authority or
external state unavailable in the workspace. A blocker in one operational wave
does not excuse leaving independent repository implementation unfinished.

## Start from the current WIP

Preserve all user-owned working-tree changes. Inspect the current diff before
editing and classify overlapping changes rather than resetting them.

The current WIP already contains sync schema, client store/runtime/projection,
publisher/Worker code, admin audit work, an additive expansion migration, and
the first receipt-backed command slice. Treat these as unverified
implementation, not as trusted completion.

Current mutation state that must be reconciled:

- `client_mutation_receipts`, `client_aggregate_versions`,
  `begin_client_mutation_v1` and `finish_client_mutation_v1` exist in the
  in-progress expansion migration.
- `mark_news_read_client_sync_v1` is the first receipt-backed command.
- The rejected cross-domain SQL dispatcher and Dart
  `ClientMutationGateway.execute(String, Map)` have been deleted and must not
  return.
- `client_commits` and `record_client_sync_commit_v1` may still contain
  transitional idempotency/result fields or behavior. Remove that conflation:
  receipts own replay; commits describe actual changes only.
- Direct PostgREST DML and multi-request persistence still exist in multiple
  features. They are migration inventory, not an acceptable v1 write path.
- The current expansion migration is unapplied WIP. Make it internally
  coherent and reviewable; do not preserve dead/commented implementations.

Run `node automation/client_sync_preflight.mjs` once before implementation.
Do not repeat completed remote baseline checks unless relevant external state
changed. Use `--remote` only for an intentional read-only baseline refresh.

## Canonical mutation contract

Standardize guarantees and lifecycle, not domain DML.

Each public command:

1. receives a command UUID created at the user-intent boundary and retained
   across transport retries;
2. derives the actor from `auth.uid()`;
3. resolves scope, ownership and referenced entities from authoritative DB
   relations;
4. rejects unknown keys, oversized input and cross-scope IDs;
5. rechecks authorization before replay;
6. claims `command_id + command_name + actor + scope + canonical request SHA-256`
   before domain DML;
7. returns the stored exact response for the same command/hash and rejects the
   same command ID with different input;
8. acquires aggregate/version or contested-resource locks in a documented order;
9. validates and performs all domain DML in the current transaction;
10. creates one audit commit, items, component revisions and dirty keys only
    when state materially changed;
11. completes the receipt with status
    `applied|unchanged|rejected|conflict`, authoritative `data`, mutation
    metadata and `sync.replacements`;
12. lets unexpected SQL failures propagate so the transaction rolls back.

Use typed scalar context/concurrency parameters and documented aggregate DTOs.
Never accept raw table rows, arbitrary patches, table names or client-supplied
audit/sync impacts. Prefer `SECURITY INVOKER`; a necessary
`SECURITY DEFINER` function must use an empty `search_path`, fully qualified
objects, explicit auth and minimum grants.

The shared kernel may own only receipt claiming/finalization, redacted
audit/revision bookkeeping, response decoding and replacement activation. It
must not own domain DML, domain authorization, a cross-domain `CASE`, dynamic
SQL dispatch or a runtime RPC registry.

Feature/UI code must use typed ports such as `EventCommands`,
`AttendanceCommands`, `MapCommands` and `ActivityCommands`. A shared
transport is internal plumbing and must not expose arbitrary RPC strings/maps to
feature code. Introduce build-time bindings or a declarative verification
manifest only after reference slices demonstrate real duplication; never
introduce runtime routing or speculative framework machinery.

## Required mutation slices and concurrency

Complete and test at least these vertical slices first:

1. Event aggregate save/delete: event plus owned roles and parent relations,
   one aggregate version and one authoritative replacement.
2. Attendance/signup/sign-out/saved-program transitions: rewrite or extract the
   current handler so event capacity, participant scheduling owner, exclusive
   groups and counseling limits serialize correctly. Do not merely wrap the
   current race-prone implementation.
3. Activities draft/publish: publishing must atomically record the PUBLISH
   history version and replace the live activity graph in one RPC.
4. Inventory aggregate: retain the useful full-bundle behavior while adding
   receipt, audit, sync and concurrency guarantees.

Then migrate map/place/place-type/path/icon, information/news/speakers,
groups/membership/private place, profile/accommodation/users/imports, cleaning,
forms, tickets and every other registry writer. For editor aggregate
replacement use monotonic `bigint` versions distinct from sync revisions. For
capacity, stock, allocation and ticket transitions lock the authoritative
decision owner before reading and deciding. Add concurrency tests that would
fail without the lock/version invariant.

Repository evidence recorded 2026-08-03 sharpens the forms/tickets portion:
online-only form/order/ticket aggregates with no client projection dependency
remain explicit domain boundaries with their own histories, while every writer
of `eshop.spots`, products, product-inventory contexts and ticket-product links
is in scope because those relations feed `private_inventory`. It also identifies
`unit_catalog` is occasion-materialized and unit-written. The repository now
uses unit-scoped receipts/commits and atomic fan-out to every visible occasion;
an arbitrary occasion is never used as a fake unit audit scope.

Repository implementation evidence on 2026-08-03 also closes two previously
implicit paths: exclusive-group relation replacement is one versioned command,
and companion lifecycle plus companion attendance advance the owner's
`private_profile`. News creation combined with notification delivery is one
transactional `publish_news_client_sync_v1` intent rather than two client
writes. Anonymous/authenticated feedback, unit lifecycle, commerce, membership,
account-deletion and external-source paths are closed in repository code. The
registry has no remaining `boundary` rows; production activation is still
blocked on the Wave 6 operational checks and deployment authority.

Repository execution was completed and verified locally on 2026-08-03. The
authoritative plan's Definition of Complete records the passing gates and the
four deliberately open operational items. Do not reopen repository waves
without new failing evidence; continue with the Wave 6 production-like load,
external audit and authorized cutover gates.

For secrets, R2/image operations, notifications or other external/long-running
effects, use an authenticated Edge boundary that invokes a narrow service-only
DB command. That command atomically records domain state plus an outbox item;
an idempotent worker performs the external effect. Edge code must not perform
arbitrary service-role table DML. Do not add Kafka, event sourcing, a general
message bus or a saga framework. `client_projection_dirty_keys` remains a
specialized projection outbox.

## Sync and consumer completion

Retain the plan’s three old-or-new consistency classes:

- structural public catalogs pinned by one release manifest, p95 target 45 s;
- small immutable `live_public`, p95 target 25 s;
- authorized private identity overlays, p95 target 75 s.

Public polling must hit only `sync.festapp.net`/R2 and never Supabase. Use one
15 s + 0–3 s jitter foreground scheduler; every fourth successful tick and
relevant lifecycle triggers may perform the private revision handshake.
Navigation joins the same freshness-gated single-flight operation. Do not use
Realtime/Broadcast, deltas, tombstones, page polling, Supabase Storage, Workers
KV, Durable Objects, `r2.dev`, or a Supabase public fallback.

Publish one immutable release manifest only after every required dirty
component is built, bounded, hashed, uploaded and verified. `map_catalog`
must contain places, place types, paths and the complete referenced SVG icon
closure; dangling references block publication. Materialized event/cleaning
live state is updated from bounded coalesced dirty keys and periodically
reconciled with authoritative tables. Projected counts never decide admission.

Move Program, Map, Information, News, Profile, Groups, Accommodation,
Activities, Search and admin consumers to canonical projections. Remove their
local-then-network loaders, page timers, direct cache keys and missing-reference
side-fetches. A successful mutation applies authoritative replacements locally
without a follow-up refresh.

## Compatibility and deletion

Keep released legacy RPC contracts only as measured external boundaries. When a
legacy contract must remain, make it a thin facade over the same canonical
domain handler and record its consumer plus retirement condition. Do not keep a
second implementation behind it, and do not wrap a legacy function that
swallows failures or violates concurrency—extract and fix the handler first.

Before capability enablement, prove every supported writer is either migrated
or force-upgraded. Ordinary roles must have no direct DML grants on canonical
application data. Do not add persistent capture triggers or commit-context
guards. Privileged break-glass writes require an explicit gateway, reason and
externally retained evidence.

Delete obsolete dispatchers, generic gateways, dual writes, direct-DML v1
branches, multi-request save orchestration, page loaders/timers, stale
registries, tests, fixtures and documentation in the same cutover. Absence
proofs must cover Dart, JS/Edge, SQL functions/grants, migrations, cron/workers,
dynamic string registrations, feature flags and generated clients. Do not
leave commented dead code.

Wave 7 contraction is a later release only for genuinely released external
compatibility. Perform it after telemetry proves its retirement criteria; do
not mislabel internal unfinished migration work as compatibility.

## Verification and finish criteria

This work touches auth, concurrency, migrations and public contracts, so use
standard verification even if the repository default is low-risk. Batch
coherent implementation before validation, but do not declare completion from
static analysis alone.

Use factories and returned IDs/revisions. Required evidence includes:

- SQL contract, auth/RLS/grant, rollback, replay/hash-mismatch, no-op,
  concurrency and component-registry tests;
- exact-one receipt and optional exact-one commit/revision assertions;
- publisher hash/budget/privacy/monotonic-pointer and reconciliation tests;
- Dart store crash-point, identity-epoch, retry, scheduler fake-clock and typed
  command tests;
- consumer call-graph and focused `rg` absence proofs;
- targeted widget/integration tests and browser smoke where appropriate;
- polling/load measurements from the plan;
- `./automation/test_all.sh` and repository release gates before an authorized
  production cutover.

If `DATABASE_URL`, Cloudflare access, production audit configuration or other
external state is unavailable, finish all independent repository work and
report the exact blocked command/gate. Do not fabricate a passing result.

Completion means every checkbox in the plan’s Definition of Complete is either
proved or explicitly blocked by an action requiring new authority. It does not
mean “the architecture is prepared”.

## Authority boundary

Do not apply production migrations, provision/change CDN/DNS/schedulers,
activate `client_sync_v1`, deploy, commit or push without explicit user
authority. Once authorized, follow the plan’s single cutover runbook:
backup/baseline → additive DB → verified initial artifacts → complete client
with capability off → release/load/privacy gates → atomic capability enablement
→ immediate online/offline/reconnect/login/mutation/audit smoke → monitoring and
tested kill switch.

Production now has pgaudit write logging for `postgres` and `authenticator`.
The owner explicitly declined a paid external Log Drain on 2026-08-03 and
accepted hosted-only audit retention plus fingerprint reconciliation for this
web-only cutover. Do not provision an external drain; record and preserve this
exception when executing the guarded activation.

At handoff report:

- gained invariants and canonical owners;
- every migrated producer and consumer;
- receipt/commit/concurrency coverage;
- sync/publisher/privacy/load results;
- deleted artifacts and focused absence proofs;
- exact retained compatibility boundaries and retirement gates;
- commands run and their results;
- unapplied production steps, external blockers and kill-switch state.
