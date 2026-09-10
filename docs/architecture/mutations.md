# Canonical application mutation architecture

## Status

Target architecture for new writes and for migrations away from direct
PostgREST DML. This document defines the application-wide write boundary; it
does not change the read model or require every domain to share one payload.

## Problem

Festapp currently contains three materially different write styles:

1. Dart composes several direct table operations. Event, map, information,
   news and group editors use this style. Authorization and constraints are
   partly RLS-driven, related rows are saved in several requests, and callers
   can observe partial success.
2. A domain RPC owns one guarded command. Event attendance, ticket scanning and
   cleaning commands use this style, but response and error conventions differ.
3. A domain RPC saves and returns an aggregate bundle. Inventory and forms are
   the strongest existing examples. Activities also save a graph, but draft
   history and live publication are currently two client-orchestrated calls.

The target standard preserves the useful domain differences while removing
client-owned persistence workflows.

## Decision

### One public RPC per user intent

Every persisted user intent enters PostgreSQL through an explicitly named
domain command RPC. Examples:

- `save_event_v1` saves the event plus roles and parent relations;
- `set_event_attendance_v1` performs capacity and conflict decisions;
- `save_map_place_v1` saves one place;
- `save_user_group_v1` saves the group, membership and optional private place;
- `publish_activities_v1` records the published history version and replaces
  the live activity graph;
- `save_inventory_pool_v1` saves and returns the pool bundle.

RPC names are the public interface. A generic RPC accepting a table name,
operation name or unrestricted patch is forbidden. A central `CASE` dispatcher
for unrelated domains is also forbidden. Shared infrastructure may finalize a
mutation, but it may not contain domain DML or domain authorization.

The command boundary follows the user's atomic intent, not the table layout.
Consequently, a command may touch one row, several relations, or a complete
aggregate graph. Internal SQL may use `INSERT`, `UPDATE`, `DELETE` or
`ON CONFLICT` when that is the correct implementation. Those operations never
become a client-controlled workflow.

### Stable command contract

Small commands use typed SQL arguments. Aggregate commands use one documented
JSON DTO after typed context and concurrency arguments. They do not accept raw
table rows.

```sql
save_event_v1(
  p_occasion bigint,
  p_command_id uuid,
  p_expected_version bigint,
  p_event jsonb
) returns jsonb
```

All command responses use this envelope:

```json
{
  "status": "applied",
  "data": { "event": {} },
  "mutation": {
    "commandId": "uuid",
    "receiptId": "uuid",
    "commitId": "uuid-or-null",
    "replayed": false,
    "occurredAt": "timestamp"
  },
  "sync": {
    "replacements": [
      { "component": "program_catalog", "revision": 42, "payload": {} }
    ]
  }
}
```

`status` is one of `applied`, `unchanged`, `rejected`, or `conflict`. `data` is
command-specific and authoritative. `mutation` and `sync` are uniform. A caller
applies returned replacements locally and does not issue a follow-up read.
Rejected business outcomes are data, not partially committed exceptions;
unexpected SQL errors propagate and roll the transaction back. Existing
released RPC contracts remain unchanged; their v1 path is adapted by a new
explicit RPC or a thin legacy facade over the same internal domain handler,
never by changing an already released return shape.

### Transaction template

Every canonical RPC follows the same order:

1. Validate bounded top-level input and derive actor from `auth.uid()`.
2. Resolve the aggregate, scope and ownership from authoritative relations.
3. Perform the domain-specific permission check.
4. Claim `p_command_id` and its request SHA-256 through the internal receipt
   helper. A committed duplicate returns the stored response; concurrent
   duplicates serialize on the unique key; reuse with a different hash is a
   conflict. Authorization is rechecked before replaying a stored response.
5. Acquire the aggregate lock required by its invariants. Capacity and stock
   commands lock the authoritative capacity owner before deciding.
6. Validate the domain DTO and optional expected aggregate version.
7. Apply all domain DML in the current PostgreSQL transaction.
8. Build the authoritative command result from the rows just persisted.
9. If state changed, append exactly one redacted audit commit, advance component
   revisions and coalesce projection dirty keys.
10. Complete the receipt with the exact response and optional `commit_id`.

Any raised error rolls back the domain rows and receipt together. An unchanged,
rejected or conflict result completes a replayable receipt but creates no audit
commit and advances no sync revision. Receipt retention must preserve the exact
response for the supported retry window and retain a longer command/hash
tombstone so pruning cannot permit accidental re-execution.

The exact-response receipt is bounded at 8 MiB and command `data` at 4 MiB.
Those bounds intentionally sit above the accepted activities and inventory
aggregate DTOs plus one private replacement; small entity commands remain far
below them. Release load evidence must include the largest real private payload
instead of assuming the bound is a normal response size.

### Narrow shared mutation kernel

The internal, ungranted mutation-protocol module is shared across domains:

- `begin_client_mutation_v1` reserves/replays the idempotency receipt;
- `complete_client_mutation_outcome_v1` completes unchanged, rejected and
  conflict receipts with the standard envelope and no audit commit;
- `complete_client_mutation_applied_v1` appends redacted audit items, advances
  declared component heads, optionally builds immediate public replacements,
  and completes the applied receipt;
- `finish_client_mutation_v1` is the lowest-level exact-response storage seam
  used by those helpers and by commands with specialized private replacements.

The helpers know about mutation receipts and sync components only. They do not
know about events, places, users, forms, inventory or any domain table. Domain
RPCs declare their affected components explicitly, and registry tests verify
those declarations against the source relation inventory.

### Four command shapes

The codebase uses four standard shapes rather than one universal CRUD API:

| Shape | Examples | Concurrency/result rule |
| --- | --- | --- |
| Entity command | place, place type, speaker, news | lock/update one aggregate root; return the saved entity |
| Aggregate replacement | event with relations, group with members, inventory pool, form | reconcile the complete owned child set in one transaction; return the complete aggregate |
| Guarded transition | attendance, ticket scan, cleaning resolve, allocation | lock the decision owner; return the exact new state and domain outcome |
| Draft/publish | activities and other versioned editors | draft is history-only; publish atomically records the version and replaces live state |

Imports are batch commands of one of these shapes. They return a bounded result
summary and one commit with many redacted items; they are not loops of client
RPC calls.

### Client structure

Each feature owns a typed command port (`EventCommands`, `MapCommands`,
`GroupCommands`, and so on). It translates models to its command DTO and parses
its result. A command UUID is created at the user-intent boundary and retained
through every transport retry. The shared internal mutation transport only:

- invokes the statically bound RPC for that typed command;
- maps the standard error envelope;
- forwards `sync.replacements` to `ClientSyncService` for atomic activation.

It is not exposed as `execute(String rpc, Map payload)`: feature/UI code cannot
select arbitrary RPC names. It does not accept a table name, infer a domain
operation, or contain a switch over every application command. UI code never
calls `.from(...).insert`,
`.update`, `.upsert` or `.delete` for canonical application data.

### Direct-client trust boundary and external effects

Festapp calls Supabase RPCs directly from untrusted clients. Every granted RPC
is therefore an internet-facing authorization boundary: it derives the actor
from `auth.uid()`, resolves scope and ownership from the database, rejects
unknown keys and oversized payloads, validates every referenced ID against the
resolved scope, hardcodes audit/sync impact, and receives the minimum exact
grant. Prefer `SECURITY INVOKER`; a necessary `SECURITY DEFINER` function uses
`search_path = public, extensions`, explicitly qualifies non-public objects and
performs explicit authorization checks.

There are two write lanes:

1. Pure PostgreSQL intent: client calls one explicit domain RPC and the whole
   mutation commits in one database transaction.
2. Secret-bearing, external or long-running intent: client calls an
   authenticated Edge endpoint, which invokes a narrow service-only database
   command that records state plus a transactional outbox item. A retryable
   worker performs the external effect. Edge code never performs arbitrary
   service-role table DML.

The projection dirty-key set is a specialized outbox. This design does not add
a general message bus, event sourcing or distributed saga framework.

### Concurrency

Editors use a monotonic `bigint` aggregate version distinct from component sync
revisions and reject stale replacements with `conflict` plus authoritative
data. Contested capacity, stock, ticket and allocation transitions lock their
authoritative decision owner in a documented order before reading and deciding.
Timestamps are not concurrency tokens.

### Controlled reuse

Share the envelope, receipts/idempotency, audit/sync finalization, response
activation, error decoding and static contract checks. Do not share domain DML,
domain authorization, lock ordering or invariants in a global dispatcher.
Stabilize two or three reference command slices first; then introduce a small
declarative contract manifest or generated typed bindings/grant tests only when
it removes demonstrated repetition. Generation is build-time verification, not
runtime routing.

### Read/write separation

Public/offline consumers read `ClientSyncProjection`. Admin editors load a
purpose-built edit bundle and save through commands. A write response updates
the active sync projection, but the editor DTO and public CDN DTO remain
separate so private/editor-only fields cannot leak into public artifacts.

### Forms, tickets, and unit-scoped commands

The component source registry covers only relations that feed a v1 public or
private client projection. Forms and most order/ticket state are online commerce
aggregates with their own RPC authorization and order history. Their typed v1
commands own receipts and audit while emitting sync revisions only for source
relations that feed `private_inventory`.

There are important exceptions. `eshop.spots`, products,
`product_inventory_contexts`, and `order_product_ticket` feed
`private_inventory`, so their ticket/form/allocation writers are listed in the
registry even though the owning commands live in the commerce domain. The same
transaction advances affected users' private-inventory revisions. The registry
checker rejects any remaining `boundary` disposition.

`unit_catalog` is materialized once per occasion but is changed by a unit-scoped
command. Unit and organization scopes are first-class ledger identities. Unit
commands fan out atomically to every visible occasion and never reuse an
arbitrary occasion as their audit scope.

For the map domain, `get_map_editor_bundle_v1` returns hidden and visible
places, place types and paths with their aggregate versions. The public
`map_catalog` contains only visible rows plus the referenced icon closure; its
visible entities also carry the concurrency version needed when an editor moves
a point from the normal map screen. The canonical write intents are
`save/delete_place_client_sync_v1`, `move_place_client_sync_v1`,
`save/delete_place_type_client_sync_v1` and
`save/delete_path_client_sync_v1`; immutable unit-owned icons use
`save/delete_icon_client_sync_v1`. Hidden-only changes are audited but do not
advance `map_catalog`, because they cannot change its artifact payload.

Occasion information and news use the same protocol module through
`save/delete_information_client_sync_v1` and
`save/delete_news_client_sync_v1`. Deleting news atomically moves affected
read markers to the immediately preceding news item (or removes the marker),
and advances the corresponding `private_news` heads. Notification delivery is
a separate intent when sent alone. When the UI requests both persistence and
delivery, `publish_news_client_sync_v1` records the news row and the existing
notification delivery log in one transaction and one receipt; the client no
longer composes two writes.

Attendance exclusivity and companions are also closed command boundaries.
`save/delete_exclusive_group_client_sync_v1` replaces the complete constraint
aggregate under a monotonic version even though it is server-side decision
state rather than a cached payload. Companion lifecycle uses explicit
`create_companion_client_sync_v1`, `delete_owned_companion_client_sync_v1`,
`assign_existing_companion_client_sync_v1`, and
`unassign_existing_companion_client_sync_v1` commands. Admin unassignment
removes only the occasion relationship. `private_profile` is the sole
identity-scoped companion projection. Admin commands advance the owner's
private head without returning that owner's private payload to the admin.

The speaker editor uses `save/delete_speaker_client_sync_v1`; competence-topic
links are children of the speaker aggregate and are replaced atomically with
it. Topics use their own `save/delete_speaker_topic_client_sync_v1` version.
`save_event_speakers_client_sync_v1` shares the event aggregate version, so a
speaker-selection edit conflicts with a concurrent event edit instead of
maintaining a second clock for the same program row.

### Coverage and cutover

The component-source registry is verification metadata, not a runtime router.
For every synchronized relation it records the owning aggregate, canonical
command RPCs, legacy writers, component impacts and test factory. CI fails when
repository scanning or database inventory finds an unclassified writer.

Migration proceeds aggregate by aggregate:

1. add and test the canonical RPC;
2. move every supported caller to its typed repository command;
3. verify response application and exactly-one receipt;
4. classify old entry points in the deletion ledger;
5. after the force-upgrade/usage gate, revoke ordinary direct DML and remove the
legacy branch.

The Dart equivalent is `ClientCommandResponse`: it validates the common
envelope and activates replacements once. Typed domain command adapters only
translate their DTO and authoritative `data` result.

The sync capability must not be enabled while a supported writer can bypass the
receipt kernel. Database-owner or service-role break-glass writes use a separate
explicit gateway with a required reason and externally retained audit evidence.

## Immediate implications for client sync v1

- Remove the cross-domain mutation dispatcher from the in-progress migration.
- Replace it with explicit event, map, content, group, profile, attendance,
  cleaning, inventory and activities command RPCs.
- Refactor the current commit helper into begin/finalize receipt helpers so
  idempotency is claimed before DML and the replay result is exact.
- Keep `client_mutation_receipts` separate from `client_commits`; only actual
  state changes create audit commits and component revisions.
- Rewrite attendance around authoritative locks instead of merely wrapping the
  current race-prone function, and make activities publish one command that
  records history and replaces the live graph atomically.
- Treat existing inventory/form bundle RPCs as migration exemplars, but align
  their future versions with the standard response and receipt kernel.
- Keep SQL conflict reconciliation internal where appropriate; remove direct
  client upserts from the v1 path.
