# One-time ticket product type cutover

This directory is offline tooling, excluded from every Edge import graph.
`legacy-layout.ts` and `legacy-import.ts` freeze the original geometry reader.
Historical SQL migrations and already delivered PDFs remain unchanged.

Run the following only with a reviewed, current inventory and explicit organization:

```sh
psql "$DATABASE_URL" -qAt -v organization=3 -f automation/tickets/product-type-cutover/inventory.sql > inventory.json
deno run --allow-env --allow-read --allow-write --allow-net automation/tickets/product-type-cutover/run.ts inventory inventory.json summary.json 3
deno run --allow-env --allow-read --allow-write --allow-net automation/tickets/product-type-cutover/run.ts dry-run inventory.json manifest.json 3
deno run --allow-env --allow-read --allow-write --allow-net automation/tickets/product-type-cutover/run.ts apply manifest.json reviewed-apply.sql 3
```

These commands read assets and generate files. They never execute apply SQL.
Dry-run fails if any configuration is unresolved; inspect `manifest.json.unresolved.json`.
The candidate set includes form references (including hidden/closed forms) and
historical purchases. Multiple used groups fail closed; unused catalog groups
do not create ambiguity. Transport products without an old print binding are
untouched. Both wide/named slots are materialized from actual resources. Missing
artwork, unknown fonts or invalid legacy shapes block conversion.

After separately authorized apply, refresh `inventory.sql` to readback.json and run:

```sh
deno run --allow-env --allow-read --allow-write --allow-net automation/tickets/product-type-cutover/run.ts verify readback.json manifest.json 3
deno run --allow-read automation/tickets/product-type-cutover/verify-runtime.ts
```

The generated SQL combines the dedicated forward definitions and conversion in
one transaction. It checks complete organization scope, locks configurations in
ID order, checks versions/full-feature hashes and validates every reference before
writing. It writes existing client-sync commit/audit/version/invalidation records
and the existing Supabase migration ledger. Its temporary operational function
is dropped before commit. Replay keeps versions/audit unchanged. No new migration
framework, persistent business trigger or customer-product rewrite is introduced.

The local rehearsal used an independently cloned disposable database, not the
shared test database. Evidence includes schema 1/2, implicit geometry, closed and
hidden forms, an unused extra food candidate, transport, both slots, replay and
whole-batch rollback on a conflicting final row. Production inventory must be
refreshed after writes/rendering are fenced; the October 13 evidence is not an
apply manifest and does not authorize other organizations.
