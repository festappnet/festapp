# Blueprint B SQL evidence - 2026-10-19

## Final source and boundary

Worktree: `/Users/miakh/source/festapp-blueprint-b-20261019`. The original dirty
checkout was not changed. No production connection, migration application,
publication, commit, push or real outbound email was performed by the SQL worker.

Forward migration: `supabase/migrations/20261019100000_blueprint_layout_integration.sql`.
Final SHA256:

```text
2c8ce0b73bd27746b1daf537f0c86651cdda64091cc2af6a48aa651340921708
```

The migration contains named canonical-source headers. Historical migrations
were not edited. Existing receipt, checkout, financial swap, cancellation,
replacement and inventory owners remain authoritative; no new money/hold ledger
or persistent application trigger was introduced.

## Disposable database identity

The task bootstrapped a new PostgreSQL project using the repository bootstrap:

```sh
FESTAPP_LOCAL_DB_WORKDIR=/tmp/festapp-blueprint-b-db \
FESTAPP_LOCAL_DB_PROJECT_ID=festapp-blueprint-b-20261019 \
FESTAPP_LOCAL_DB_PORT=59432 ./automation/bootstrap_local_db.sh
```

Database container: `supabase_db_festapp-blueprint-b-20261019`, ID prefix
`717ebfc5d02f`, published port `59432 -> 5432`. Docker Compose and Supabase labels
both identified `festapp-blueprint-b-20261019`. The local listener was Colima's
SSH multiplex connection, not a production tunnel. A TCP SQL query and a separate
`docker exec` SQL query returned the same disposable marker and PostgreSQL system
identifier `7698302524285648938`.

The connection argument below is sanitized as `$TASK_DB_URL`; it was the local
Supabase admin connection to this task database. Existing Docker projects were
inventoried and were not reset or modified.

## Actual SQL checks

These are the last focused commands and selected counts. They passed separately
as their owning behavior was completed. This is not a claim that a final combined
five-file batch was run after every later correction.

| Command suffix after `DATABASE_URL="$TASK_DB_URL" node web_client/scripts/run_db_tests.js` | Selected / result | Scope |
| --- | --- | --- |
| `database/tests/blueprint/layout_integration_test.sql` | 1 / 1 passed | Save, replay, revision conflict, late-error rollback, binding identity, atomic holds, blocked member rollback, public privacy, strict geometry rejection, backend order-selection total/currency. Last rerun after save performance correction. |
| `database/tests/blueprint/finance_integration_test.sql` | 1 / 1 passed | Paid swap preview rollback, committed price/payment/assignment changes, currency rejection, partial-unit rejection, complete used couch cancellation/replacement/swap rejection with unchanged assignments/state. Last rerun after shared used-unit guard. |
| `database/tests/blueprint/capacity_resources_test.sql` | 1 / 1 passed | Standing binding, supply/pool/product limit minimum, context quantity, rejection below allocations, atomic capacity rollback, service-only outline registration and glyph merge/read projection. |
| `database/tests/blueprint/copy_setup_test.sql` | 1 / 1 passed | New IDs and remapped references/bindings/products/context/pool, no copied holds/order links, revision zero, valid empty setup blueprint. Last rerun after copy UUID correction. |
| `database/tests/blueprint/authorization_test.sql` | 1 / 1 passed | Actual authenticated wrapper denial for order-only actor, same internal denial, no revision/bindings/receipt changes, editor without order rights succeeds, manager-only succeeds. Last run against final authorization change. |

The runner reports selected count and summary; a zero-selected exit was not used
as evidence. Its global sequence setup ran only on the owned disposable database.
Canonical changed SQL was applied with `psql -v ON_ERROR_STOP=1 -f <source>` before
its focused check. The complete migration also compiled on the task database;
later corrections were applied as their exact changed canonical sources.

## Two-connection concurrency

Actual command:

```sh
BLUEPRINT_DATABASE_URL="$TASK_DB_URL" \
  node web_client/scripts/blueprint_concurrency.mjs
```

Receipt: `PASS 8 deterministic two-connection blueprint races;
database=festapp-blueprint-b-20261019`.

The harness observes `pg_blocking_pids` before committing the first connection;
it does not infer serialization merely from a fixed sleep. Scenarios:

1. Save versus save with distinct commands and the same expected revision:
   first applies, waiting save rejects stale revision.
2. Hold wins before save: waiting metadata edit rejects protected seat.
3. Save blocks seat before hold: waiting hold rejects unavailable seat.
4. Reverse-direction swaps serialize without reversed spot-lock deadlock.
5. Hold versus swap preview: preview rechecks the committed hold and rejects.
6. Geometry save versus real finalization: waiting finalizer succeeds with the
   same held physical spot identity.
7. Geometry save versus existing cancellation owner: waiting cancellation marks
   the ticket cancelled and releases the same spot.
8. Geometry save versus replacement whose finalizer fails after preparation:
   rejected replacement restores the old ticket state and spot assignment.

These eight races preceded the later used-unit, copy-identity and authorization
corrections. The lock structure was unchanged by those corrections; the races
were not redundantly rerun. Their new rules received the focused tests above.

## Size and performance

Actual profiled command:

```sh
BLUEPRINT_DATABASE_URL="$TASK_DB_URL" BLUEPRINT_SEATS=20000 \
BLUEPRINT_PROFILE=1 node web_client/scripts/blueprint_response_limits.mjs
```

Recorded output:

```text
PASS 20000 seats: data=3953790 receipt=3954608 bytes; layout not echoed; save_ms=2898; validator_ms=2337
```

The fixture seeds a complete synthetic binding snapshot, then performs a valid
geometry save through the real receipt wrapper. Titles deliberately enlarge the
binding projection. Bytes are measured by PostgreSQL over the actual result data
and stored receipt row, including receipt metadata. Both remain below the
4 MiB data / 8 MiB receipt bounds. Geometry is not echoed in the mutation result.
The separately profiled validator call is not included twice in `save_ms`.
These numbers are observations on a busy local machine, not a benchmark SLA or
an interactive-rendering result.

Before the focused set-check optimization, 5,000-seat save measured 2,213 ms and
a 20,000-seat save was observed still active after 44 seconds. After correction,
5,000-seat save measured 1,198 ms (standalone validator 784 ms), and the 20,000-seat
measurement above completed in 2,898 ms. Save builds node/unit maps once. Exact
binding-set verification uses unique node PKs, validity of every retained binding
and equal seat/binding cardinality rather than a correlated full-node scan.

An earlier 24,000-seat successful receipt fixture was invalid evidence because
the public core permits at most 20,000 seats, separately from its 25,000-node
limit. It was superseded. A 20,001-seat rejection is now explicitly tested.

## Corrected contracts and parser proof

- V2 wrapper and internal save require occasion editor OR manager. Order-only
  permission does not authorize hidden geometry edits. The legacy no-layout
  branch and order/swap operations retain their existing permission contracts.
- Shared selection-unit validation rejects incomplete sets and any complete
  unit containing a used ticket. Swap, cancellation and replacement reuse this
  guard. Existing singleton mutability behavior is preserved.
- Copy generates fresh declared UUIDs for nodes, sections, selection units,
  attachments, generators and presets, including nested preset documents. One
  recursive rewrite changes only declared identity/reference fields:
  `id`, `parentId`, `rootId`, `assemblyId`, `seatId`, `targetId`, `nodeIds`.
  The same map changes seat/group/area binding node IDs and membership IDs.
  Labels/text that happen to equal a UUID remain unchanged. The earlier claim
  that copied geometry should preserve UUIDs was wrong and was corrected.
- New binding tables use the canonical `postgres` owner so the existing
  occasion-copy SECURITY DEFINER owner can insert. Application table writes
  remain revoked; this fixed a real copy permission failure.

The actual corrected copied document was exported from a rollback-only SQL
fixture and passed the package public consumer:

```sh
fvm dart --packages=/Users/miakh/source/venue_seat_picker/.dart_tool/package_config.json \
  /tmp/blueprint_copy_validate.dart
```

Output: `PASS copied fixture public core parser + document validation`.
The consumer called `VenueLayoutDocument.fromJson` and `validateDocument`.
The SQL test separately proved disjoint original/copied node sets, remapped
record/reference families, preserved UUID-looking label, remapped commercial
identities and absence of copied holds/orders. The initial corrected E2E
geometry fixture passed the same public parser as well. Synthetic outline data
in SQL fixtures is not evidence of real font appearance.

## Reconstructing the real public form fixture

Load test helpers only into the marked disposable E2E database. Register a real
canonical font outline through the existing resolver/service path first. Its
registered glyph set must cover `Mixed tableAtomic couchStanding`.

```sh
psql "$TASK_E2E_DB_URL" -v ON_ERROR_STOP=1 \
  -f database/tests/blueprint/fixtures.sql \
  -f database/tests/blueprint/e2e_fixture.sql

psql "$TASK_E2E_DB_URL" -v ON_ERROR_STOP=1 -v font_id="$REGISTERED_FONT_ID" <<'SQL'
SELECT public.blueprint_seed_e2e_fixture(:'font_id', 1);
SQL
```

Organization `1` is the seeded local TestOrg; one-argument and no-argument helper
arities remain available for isolated SQL tests. Helpers reserve both occasion
and form links through `reserve_public_link_internal(..., true)` at creation.
The E2E form has a required visible top-level `ticket` field (`max_tickets: 20`),
a visible `spot` ticket child, the offered `product_type` child and required
contact email. Spot itself is optional so standing ticket items need no fake
spot identity. The previously incomplete fixture displayed only CONTINUE and
could not reach the picker; that was a fixture defect, not a business fix.

For the already-created synthetic form `2`, the idempotent repair is:

```sh
psql "$TASK_E2E_DB_URL" -v ON_ERROR_STOP=1 -v fixture_form=2 \
  -f database/tests/blueprint/repair_e2e_form_fields.sql
```

Actual reconstruction verification used the owned task DB and explicit tenant
`1`, cleared the JWT subject, called `get_form_by_link` and `get_blueprint`, then
fed the actual returned public form into production JS `FormModel`. Both readers
returned 200. The model had a visible ticket max20, grouped visible spot child,
required email and blueprint ID; the public standing snapshot reported available
5. This proves the fixture contract, not a completed browser checkout.

## Limits of this evidence

- Verified image/background persistence was subsequently implemented and tested
  through the same Worker/SQL owners; see [image evidence](image-evidence.md).
  Unknown/unready scoped assets still reject with `BLUEPRINT_ASSET_RESOURCE_NOT_READY`.
- SQL tests use synthetic customers, prices, capacities and outline fixtures.
  They do not prove real provider delivery, payment reconciliation or font
  rendering.
- Targeted geometry rejection tests do not constitute exhaustive conformance
  testing of every generic core authoring/style combination.
- Full Flutter/UI/JS browser execution, screenshots and final integration are
  owned by the coordinator/UI worker; this report does not substitute for them.
- No production activation, V1 live conversion or deployment was performed.


## Coordinator final batch

The final canonical SQL sources were checked together on the owned SQL project
with the existing runner: five explicit blueprint test files selected, five passed,
zero failed. The connection role must be supabase_admin, matching the previously
created test fixture function owner. A first attempt as postgres failed42501 before
scenario execution, then the correct disposable admin role passed. No application
permission was broadened to accommodate the test runner.


## Final public scope correction

Actual compiled anonymous Flutter parsing required occasion, which the public
reader had omitted. The final public reader now returns b.occasion after verifying
the requested form belongs to that blueprint. This is public event scope, not an
internal inventory or order identifier. Applied only to full disposable DB59522.
The affected real layout integration suite selected1/passed1 again, including
occasion equality and the existing no-private-data assertion. The other four
passing SQL suites have unchanged covered source. The final migration hash above
includes this one-field correction; the earlier five-file batch preceded it.
