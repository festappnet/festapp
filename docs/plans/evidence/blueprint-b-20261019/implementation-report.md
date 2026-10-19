# Blueprint V2 implementation and canonical cutover

The host now uses one canonical V2 layout/binding contract. V1 rendering and
writing paths have been removed. The54-row acceptance ledger links actual UI,
host and SQL evidence; its remaining final checks are stated explicitly rather
than inferred from older passing runs.

## Scope and preserved workspaces

Implementation is uncommitted in isolated worktrees, preserving both original
working copies:

- Festapp: `/Users/miakh/source/festapp-blueprint-b-20261019`, branch
  `feat/blueprint-b-integration-20261019`, base `f929d0b33eabdcd3fb6ae241cb42d919a4bec878`.
- Package: `/Users/miakh/source/venue-seat-picker-blueprint-b-20261019`, branch
  `feat/blueprint-b-host-seams-20261019`, base `c829a33d07de9a8fa376b407658875d22abd246e`.

Core, Flutter and JS remain independent public packages. Festapp owns catalog,
prices, stable spots, authorization, receipts, reservations and money. Existing
SQL/Edge order, cancellation and swap owners remain authoritative. Presentation
updates preserve geometry, camera, pending selection and later unsaved edits.

## Existing plans and Basic appearance

Read-only canonical-backend inventory found49 plans across4 organizations and4516
physical spots. All49 have deterministic converted V2 documents retaining exact
source spot identities, product assignments and labels. All49 final native documents passed actual
reviewed SQL migration and receipt replay on synthetic local owner/spot identities,
in one transaction rolled back completely. Ordered, used and held spot facts are
preserved; the demo plan has a narrow private migration boundary while normal demo
writes remain forbidden. No live plan was modified.

The rejected bitmap conversion has been replaced with native editable reconstruction. All49 plans passed the fresh matched-camera visual review.
The final documents retain4516 exact physical IDs and positions,18 native hall reconstructions,464 real tables, native table captions/architecture/zigzags and five empty layouts. Zero raster backgrounds remain. The public Original preset supplies native Basic V1, with mildly rounded tables and each hall palette kept in document appearance (including purple and white exceptions); chairs use the common31/40 marker ratio. Used purple chairs have no cross, and hover tooltips retain public seat/product/price detail. The230 unassigned physical seats remain
visible green and unavailable. No genuine orphan was found; nothing was deleted.

The self-contained private gallery is outside git at
`/Users/miakh/source/festapp-blueprint-b-e2e-20261019/preview/blueprints-native-review.html`.
It defaults to23 plans sold or offered in2025/2026, with year filters, all49 and
zoomed side-by-side original/V2 views. It makes no network requests and includes
no order, customer or hold secrets. See [Basic evidence](ui/basic-review.md) and
[inventory](existing-blueprints-inventory.md).

## Business proof and deleted alternatives

Actual disposable UI flows created JS order8 (4 tickets/360CZK) and Flutter order19
(2 tickets/180CZK), including standing admission. Admin replacement order20 created
3 tickets/350CZK with partial/full cancellation verified in SQL. Same/different-order
swaps retained authoritative ticket identities, payment facts and history. Wizard
occasion104/blueprint55 retained edited group identity and15 fresh bindings without
foreign products, holds or orders. Actual PNG/SVG upload, processing, render,
save/reload and removal passed through the existing Image Worker contract.

Old Flutter controls/groups/legend/mobile-scroll implementation, seat adapter,
JS renderer/gestures/transforms/styler/tooltips and the obsolete update_blueprint
writer were removed. Runtime readers require layout/bindings; geometry failure
cannot select V1. Legacy DTO parsing is restricted to reviewed offline migration.
Client-sync `_v1` names identify receipt protocols, not geometry alternatives.
See [deletion ledger](ui/cutover-ledger.md).

## Verification and operating boundary

[Validation receipts](validation.md) distinguish historical and final input sets.
Nine real two-connection races pass, including product maximum and addressed/shared
inventory admission. Financial, revision, protected structural mutation, role,
image, setup/copy and reviewed migration tests use the actual local database.
Separate pub/core/Flutter/npm archives and clean consumers are required gates.
UI and graphical review are owned by `gpt-6-astra`, medium, using `ui-ux-pro-max`.

Production was inspected read-only with the protected backend-access skill. No
production migration, conversion, deployment, package publication, external
notification, commit or push was performed. The approved conversion bundle and
reviewed source hashes are private local artifacts. Production resource upload,
reviewer scope, coordinated compatible clients and activation are the concrete
remaining operating step described in [activation C](activation-c-boundary.md).
