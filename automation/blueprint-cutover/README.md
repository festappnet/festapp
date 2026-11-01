# One-time canonical blueprint cutover

Active application layouts have one contract: `eshop.blueprints.layout`, schema
2, and canonical seat/group/area binding tables. Runtime copying, public viewing,
email delivery, scanning and authoring consume that contract. Conversion is an
explicit offline operation, never a fallback inside a copy or read RPC.

The reviewed 2026-11-01 inventory contains 28 old plans and 432 physical spots in
organizations 1, 3, 7 and 11. Plan 92 has an empty schema-1 document; the other 27
have the former column representation. The raster-only hall is reconstructed as
25 native editable tables, with its 172 original spots and table names. Source
exports, actual geometry, resources and prepared proposals are protected private
operational inputs, excluded from this repository.

Preparation requires a mode-700 input directory with `source.json`, and reviewed
`native<ID>.json` reconstruction where needed. Run one Flutter task at a time:

```sh
fvm flutter test --no-pub --concurrency=1 automation/blueprint-cutover/prepare_test.dart \
  --dart-define=BLUEPRINT_CUTOVER_DIRECTORY=<protected-directory>
deno run --allow-read --allow-write automation/blueprint-cutover/prepare_text.ts <protected-directory>
```

Preparation checks exact physical identity, world positions, titles, grouping,
blocked state and product assignments. Font preparation uses registered bundled
fonts and fails on network/storage fallback. Preview the actual prepared layout
through the verified renderer before sealing the release.

Publish and validate canonical main first. Upgrade the approved old frontend
`prod/farnostopava` before changing its live data. Its canonical origin is
`farnostopava.festapp.net` on Cloudflare Pages project `farnostopava`; the former
Netlify `rezervace.farnostopava.cz` site only redirects. The other approved current
frontend is `prod/festapptickets`.

```sh
python3 automation/blueprint-cutover/build_bundle.py \
  --directory <protected-directory> --source-sha <published-main-sha> \
  --database <verified-canonical-database>
```

The bundle reads operation, forward migration and catalog parity expectations
from the published commit. The administrator verifies host/database/activation,
source and bundle digests, backup/PITR readiness and captured rollback evidence.
Run the sealed `dry-run.sql` first, then `apply.sql` through the protected backend
SSH workflow. Neither executes synthetic fixtures or impersonates a customer.

One transaction checks the exact source/revision and complete old-plan set,
locks canonical inventory scopes, registers immutable text resources, writes
canonical nodes and bindings, clears all old columns (including canonical rows
with retained obsolete values), installs the forward schema/functions, verifies
catalog parity, records the migration ledger and notifies PostgREST. Full stored
spot/order/item/ticket/product/form/payment facts must hash identically before
and after. Stale preparation, an unmapped spot or any commercial mutation aborts
the entire operation. Client sync receives ordinary private inventory invalidation.

Schema constraints reject null/old/malformed root documents and every write to
the four retired geometry columns. Their physical nullable columns remain for
applied migration history, with no stored second representation. Three obsolete
RPC/helper identities are dropped. `legacy_converter.dart` is retained only as
an offline input boundary and test dependency, outside application `lib`.
The public synthetic demo fixture also creates canonical layouts directly.

Former cloud databases and frozen staging/retention schemas are outside the
active application boundary. Applied historical migrations remain immutable.
Record actual deployment and migration receipts after execution; preparation and
passing local checks do not imply production completion.
