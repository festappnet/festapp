# Ticketing authoring and issued-ticket operations through MCP

Date: 2026-10-20. Status: tool design proposed; selected backend prerequisites
partially implemented locally; no tool or live activation.
Implementation verification: standard (shared contracts, permissions, payments,
concurrency and forward database migrations).

## Outcome and authority

This is the ticketing-write child of the authoritative
[canonical operations plan](festapp-canonical-operations-plan-2026-10-20.md).
It extends phase 3 beyond the four-read bootstrap. Creating/editing seating
plans, ticket artwork, forms, products, pricing and capacity, and editing issued
tickets are required deliverables. Hosted parity follows phase 4's
[delegation gates](festapp-remote-mcp-plan-2026-10-20.md).

The backend execution prompt separately authorizes local backend prerequisites
and necessary current-client routing. See [the execution record](../architecture/operations/backend-refactor-execution-2026-10-20.md).
It does not authorize CLI/MCP/OAuth implementation, production SQL, opening sales,
modifying real tickets, sending mail or publishing a connector.

SQL domain commands remain the business authority. Shared handlers in
`tools/festapp/src/operations` supply typed arguments/results to both CLI and MCP;
MCP never drives the admin UI, executes arbitrary SQL or imports a whole admin
screen model as a write payload. Edge/Worker execution remains for actual media,
PDF, delivery or other external work. Two related database writes become one
domain transaction where they form one intention; unrelated actions stay separate.

## Concrete tool surface

Names below are proposed operation contracts, not claims that matching RPCs
already exist. Register fixed schemas as `festapp_<domain>_<action>` tools;
there is no generic `execute(operation,payload)` tool. Register only capabilities
enabled for the connection and family readiness gate. The table defines the
required scope; closely related readers can share a bounded projection.

| Operation | Inputs and observable result | Canonical owner / boundary |
|---|---|---|
| `ticketing.capabilities` | Occasion; allowed actions, supported layout/object/field schemas, limits and resource references | New bounded reader using current backend roles; no customer/hold secrets |
| `blueprints.inspect` | Blueprint or occasion; minimal geometry, stable seat IDs, product refs, occupancy counts and aggregate version | New authoring projection; do not return `get_blueprint_for_edit`'s order/customer bundle |
| `blueprints.create` | Occasion, title, bounded geometry and optional form attachment; persisted ID/version and seat-ID replacements | Canonical blueprint command; atomically attach when attachment is part of creation |
| `blueprints.save` | ID, expected version, explicit geometry/seat changes; updated version and replacements | `update_blueprint_client_sync_v1` after atomicity/scope repairs |
| `blueprints.validate` | Proposed geometry plus current references; diagnostics and optional static SVG | Pure validation/shared schema; advisory, does not hold seats or approve commit |
| `forms.inspect` | Form; editable fields/settings/product refs, deletion eligibility, version | Minimal authoring projection over canonical form read rules |
| `forms.create` | Occasion, title, link; closed form ID/version | `create_form_client_sync_v1`, extended atomically if current creation cannot guarantee closed state |
| `forms.save` | ID, expected version, explicit field/settings patch and deletion ID lists | `update_form_client_sync_v1`; preserve omitted values and existing usage guards |
| `forms.set_availability` | Form, expected version, explicit open/close/schedule intent | Canonical form writer with full capacity/waitlist/blueprint checks; separate deliberate sales activation |
| `products.save` | Product, expected version, explicit pricing/configuration and inventory-context patch | Canonical product command from parent 1E; omitted contexts preserve, `[]` clears |
| `pricing.save_wave_target` | Existing/new wave plus target and version preconditions | Atomic wave/target operation from parent 1E; no create-then-save gap |
| `inventory.save_pool`, `inventory.save_resource` | Scoped pool/resource, version, capacity/configuration patch | Existing receipted inventory owners after CW06-CW08; preserve allocation constraints |
| `ticket_layouts.inspect` | Occasion; supported schema, current layout/background/type and revision | Minimal layout projection; use current SQL/renderer schema, not a guessed version |
| `ticket_layouts.save` | Occasion, baseline revision, expected layout and narrow next appearance | Canonical occasion command with `ticket_layout_change:{expected,next}` and narrower layout permission |
| `ticket_layouts.preview` | Candidate template, authorized assets and synthetic sample values | Existing preview renderer; no issued ticket or customer email; explicit PDF generation remains separate |
| `tickets.inspect` | Issued ticket ID; allowed changes, products/seat/status and revision | Bounded authorized read; customer fields only when separately permitted |
| `tickets.change_products` | Ticket, expected revision and product selections | `update_ticket_products_client_sync_v1`; server calculates prices/payment/capacity effects |
| `tickets.swap_seats` | Exact ticket/seat identities and baseline revisions | Existing canonical seat-swap command; lock both sides and revalidate availability |
| `orders.update_responses` | Order, expected revision and typed form-answer changes | Canonical order-response writer; enforce field ownership and editability |
| `orders.create`, `orders.cancel`, `tickets.cancel` | Exact scoped intention and command identity | Existing receipted order/ticket commands; preserve automatic notice and capacity rules |
| `tickets.export`, `tickets.resend` | Exact ticket/order selection; output or explicit delivery intent | Existing authorized PDF/delivery workflow; separate export/send capabilities and durable send identity |

Templates and issued tickets are separate resources. Changing artwork does not
change ticket identity, QR secrets or already delivered PDF bytes. Changing a
ticket's products or seat does not silently send an email. Preserve the current
explicit notification choice after product edits. Manual payment adjustments,
refunds, bank access, hard deletion and external invoice deletion are separately
privileged operations, not implicit powers of a form/layout editor.

## Confirmed weaknesses and required repairs

### Blueprint rejection currently needs a rollback boundary

**Source fact:** `database/functions/eshop/update_blueprint.sql` can change earlier
spots and later return a JSON rejection when a later product is invalid or an
omitted spot is held/ordered. It updates submitted spot IDs without a blueprint
predicate in that body. Its held/ordered deletion error includes `secret`,
`secret_expiration` and `order_product_ticket`. The wrapper in
`supabase/migrations/20260802234000_client_sync_v1_expansion.sql`,
`update_blueprint_client_sync_v1`, calls `update_blueprint_internal_v1` and
completes a rejected receipt on non-200 JSON without its own rollback block.
These are source findings; deployed function resolution has not been inspected.

**Decision:** extract the effective chain into canonical authored SQL and validate
all object/product/form ownership before effects. Every spot update/delete must
also constrain blueprint and occasion. Reject caller-supplied occupancy/order/
hold data. Existing database IDs and temporary creation IDs are distinct and
mapped in command replacements. Do not delete/recreate sold seats to simplify
geometry replacement.

Begin the receipt before a domain mutation subtransaction. Convert a domain
JSON rejection into a controlled exception inside that block, roll back all
domain effects, then finalize the rejected receipt outside it. Use the existing
`replace_blueprint_order_client_sync_v1` pattern, adapted without copying a
second receipt engine. Unexpected database faults retain their real failure
semantics. Merely returning an error object does not roll back prior writes;
[PostgreSQL exception blocks](https://www.postgresql.org/docs/17/plpgsql-control-structures.html)
roll back persistent changes inside the block.

Lock affected spots in deterministic order and recheck live holds, orders and
product allocations under lock. Match the admission/lock rules in
`database/functions/eshop/select_spot.sql`; a preview is not a reservation.
Return scoped conflict identifiers/counts, never hold secrets or customer rows.

### Form and geometry writes lack a required editor baseline

**Source fact:** the form/blueprint command wrappers in that migration do not
require an expected aggregate version. `BlueprintModel` serializes an admin
bundle including products, tickets and orders. The form draft already has
explicit `deletedFieldIds`/`deletedProductIds`; the tool must retain that intent.

**Decision:** add versioned minimal reads and use existing aggregate-version
machinery. Every authoring write compares its original baseline under lock and
all competing writers advance that version. For the existing JSON contracts,
reserve an explicit `expected_aggregate_version` control field consumed by the
command, not stored in the business document; avoid ambiguous PostgreSQL default
argument overloads. Typed ticket/order wrappers must choose one similarly
unambiguous precondition contract before registration. Stale submissions return
a conflict and require reread/review, never automatic rebase and overwrite.

A compatibility adapter cannot infer what an old editor originally read. Record
the exact supported-client fence, upgrade or explicit precondition requirement
for unconditional legacy writers. Do not claim protection from lost edits while
those writers can still overwrite new saves. Keep supported public contracts
until their removal/upgrade authority is established; otherwise keep the affected
MCP write family disabled. Readers and unrelated ready families can proceed.

For forms, omission preserves and explicit deletion lists remove. Reuse usage
guards covering actual answers, order products (including cancelled orders),
blueprint spots, shared groups and inventory links. Verify rejection atomicity
for the form chain too; do not assume every error-shaped return is effect-free.
Preserve distinct-ticket capacity accounting, unpaid allocations, waitlist/offer
states and the prohibition on simultaneous active blueprint and participant
capacity/waitlist configuration. An invalid patch must change nothing.

### Artwork is a narrow, permissioned change

**Source fact:** `database/functions/others/ticket_layout.sql` validates schema
version 3 and `merge_ticket_layout_features` supports expected/next layout
changes. `can_edit_ticket_layout` uses unit-editor permission, which must not
be widened to ordinary order editing. `ticket_layout_saver.dart` limits copied
appearance properties and checks the original editor revision.

**Decision:** preserve the narrow layout change and baseline through the SQL
writer. Never resubmit stale whole-occasion features. Validate supported schema,
bindings, fonts, QR constraints and bounds using shared existing contracts;
unknown schemas cannot be downgraded. Read limits from the current capability
contract rather than freezing today's version forever. Accept only scoped owned
media references, with bounded Worker upload support if needed; never fetch
arbitrary model-supplied URLs. Persist dynamic bindings, not actual customer data.

Before exposing export/reprint, trace whether each existing renderer uses a saved
snapshot or the current layout. Document that result and expose the actual
layout revision in preview/export results. Do not promise that old downloads or
emailed files update when a template changes.

### Visual ticket design is a primary deliverable

The user's clarification prioritizes the appearance of the ticket itself.
Success includes a usable visual design loop, beyond valid template JSON or
changes to ticket/order data. Support instructions such as changing background,
font hierarchy, alignment, spacing, logo placement and prominence of event,
date, seat and admission information within the existing template schema.

`ticket_layouts.inspect` must expose available presets, registered fonts and
owned image/background references. `ticket_layouts.preview` must accept an
unsaved candidate and return a viewable image through MCP image/resource content,
plus its exact draft/scenario identity and diagnostics. Returning only a layout
object or a filesystem path inaccessible to the MCP client is insufficient.
For hosted clients use authenticated, bounded artifact access with expiry;
never public customer-bearing previews. Use synthetic sample data by default.

The workflow is inspect -> compose/edit a draft -> render and visually inspect
-> refine -> validate a final PDF -> save the reviewed candidate. Draft changes
are in memory or bounded recoverable draft state and do not change the active
layout. Saving uses the original expected revision. Return the draft fingerprint
with previews and save results so an older in-flight render cannot be mistaken
for the current candidate. Creating alternate compositions must not create
multiple live templates or activate unreviewed drafts.

Reuse `lib/components/ticket_layout/README.md` boundaries: the shared registered
font catalog, PDF-point geometry, background crop/transform and canonical PDF
renderer. Do not build a separate approximate renderer whose output diverges
from downloads/email. Render a raster view of the canonical preview PDF when
needed for MCP visual inspection; explicit PDF preview/export has its own bounded
execution rather than requesting PDFs after every small draft edit.

Validate long event/product names, Czech diacritics, missing optional values,
different seat labels and each configured wide/named variant. Check text clipping,
wrapping and overlap, visual hierarchy, legibility, background contrast, QR quiet
zone/size and actual print dimensions. Use existing executable validators and
shared fixtures for mechanical constraints; visual review judges composition
and readability. QR samples remain synthetic and invalid for entry. Layout
validation cannot by itself certify that a ticket looks good or guarantee
physical scanning under every printer/paper condition.

**3B acceptance:** an MCP operator can request a design change, see the resulting
ticket image, refine it and produce a PDF matching the reviewed saved revision.
Include representative short/long text and diacritic samples, compare against
the existing Flutter preview contract, and visually inspect the canonical PDF
at actual size. A successful save of JSON alone does not pass this gate.

### Command identity must outlive transport and compare exact ownership

**Source fact:** `ClientCommandTransport.invoke` generates an ID per invocation
and overwrites `p_command_id`; retries within that invocation reuse it.
`ClientCommandIdentity.claimIntent` keys pending work by namespace/payload hash,
with a separately checked principal binding. `completeIntent` clears by payload
without comparing the completing command ID. Canonicalization preserves array
order. SQL `begin_client_mutation_v1` compares actor/scope/name/hash and retains
expired receipts as tombstones.

**Decision:** use an immutable intent handle bound to backend, actor, operation,
scope, normalized payload, original expected revisions and command ID. Persist
before submission. Clear only that exact ID/principal using an atomic local
compare-and-clear; a delayed completion cannot erase a newer intent. Preserve
existing unresolved payment intents during any local-store migration and never
rebind them across identities/backends. Normalize set-like IDs once before hash
and submission; geometry/field arrays retain meaningful order.

Timeout, reconnect and reauthorization as the same actor reuse the same request
and ID. Changed content or a newly reviewed baseline is a new intention after
the prior outcome is resolved. Expired receipts are explicit non-replayable
outcomes, not permission to generate a new ID and repeat. Destructive commands
need authorized receipt recovery even after their resource is gone; reuse
`get_order_deletion_context_v1` rather than requiring the deleted row first.

## Execution waves and deletion conditions

### 3A. Start with visual design preview (E0), complete reads by E5

Use the parent E0-E6 schedule. Reuse the context/session, handler and stdio
parts of the [read-MCP child](festapp-operations-plan-2026-10-20.md) immediately;
do not wait for report/order readers or unrelated 1A-1H families. Start with
layout inspect/resources and explicit preview using existing resolve/PDF modes,
synthetic samples and a thin image/resource output adapter. No active layout
changes are made in E0. Complete all four promised domain readers by E5.
Add minimal authoring projections and capability schemas as domain-owned
readers. Bound geometry sizes, field/product counts, asset sizes and pagination
using existing supported contracts. The current blueprint schema must be traced
from effective source/readers; proposed blueprint-v2 documents are not evidence
of a deployed schema. Start the shared fixture with two scoped identities and
synthetic layout data for E0/E1. Extend it for E2-E4 with a second occasion,
held/sold/free seats, a used form field and an issued order; these later data
requirements must not delay the first layout preview.

**Validation/exit:** E0 returns a viewable canonical synthetic preview through
MCP with correct profile/permission checks. Reader tests for later projections
prove bounded results without buyer/hold secrets as those tools are added.
Initial four-read completion by E5 is a
bootstrap milestone, not completion of ticketing MCP.

### 1I then 3B. Repair canonical writers and enable authoring by family

Gate each family on parent 1I: effective definition extraction, zero-effect
rejection, ownership, version/legacy-writer fence, persistent intent/replay and
documented side effects. Move Flutter/web callers to the same corrected owners;
remove their alternative full-document writers and duplicate validation decisions
where server authority replaces them. Retain UI validation as user feedback.
Extend canonical form creation to guarantee closed creation in the same commit
if needed; never implement create-then-close. Keep open-sales explicit.

Execute E1 layout saving first, E2 geometry/form repairs next and E3 product/
pricing/inventory consolidation next. The layout slice must not wait for
blueprint repairs; blueprint writes must not skip those repairs. Implement
fixed-schema geometry generation/editing, template/layout preview/save, form
fields/settings, products/waves and inventory handlers using shared infrastructure.
No second canvas, font catalog or renderer is part of these slices. Creating a 20-row
seating layout can generate bounded geometry in-process, validate it and submit
one canonical command. A complete event setup is a workflow of independently
valid closed resources with returned IDs/revisions and resumable checkpoints,
not one giant SQL transaction or an atomicity promise across asset uploads.
Failed attachment/upload does not silently publish a form. Explicitly report
unattached resources and safe resume/cleanup; keep media Worker recovery ownership.

**Validation/exit:** rejected mixed-validity geometry changes nothing; foreign
seat IDs fail; concurrent hold/order versus deletion preserves allocations;
stale saves conflict; form omissions preserve, explicit used-field deletion
fails; duplicate create retries return one resource; layout-only save preserves
unrelated features and enforces unit permission. Preview/save round-trips through
the same schemas. Each enabled family has a named owner, no active alternate
writer and a tested supported-client policy. Others remain visibly unavailable.

### 3C. Add issued-ticket and order lifecycle tools (E4)

Use canonical product-change, swap, response-edit, create and cancel commands.
Retain server price/payment/capacity calculations, receipted side effects and
current mutability rules from `update_ticket_products_ws.sql` and ticket command
owners. No raw `paid`, price total, ticket symbol or QR-secret patch arguments.
Add export/reprint and manual resend with separate capabilities and explicit
intent; never make editing imply delivery. Do not expand this wave into bank or
refund administration. Register operation metadata accurately, including any
preview/export that actually creates assets or durable jobs.

**Validation/exit:** product edit with capacity/payment implications, concurrent
swap, order-response field ownership, cancellation automatic-notice dedupe,
timeout replay and delayed completion clearing are covered by targeted SQL and
adapter tests. Use fixture mail/PDF services. No real recipient or charge.

### 4D. Carry the same enabled operations to hosted grants (E6)

Follow the remote plan's operation-specific grants and write admission semantics.
Share handlers and result schemas; hosted token/consent policy is an adapter
boundary. Test grants for design-only, sales activation, issued-ticket changes,
export and delivery independently. Publishing and enabling real writes require
the separately authorized selected-tenant release.

## Completion and residual uncertainty

The ticketing scope is complete when an authorized operator can create a closed
form and seating plan, configure products/capacity, iteratively design ticket
artwork with viewable previews and a matching final PDF, explicitly enable sales, and perform permitted issued-ticket edits
through local MCP, with canonical backend owners and passing conflict/replay/
authorization tests. Hosted clients have equivalent operations only after 4D's
delegation checks; a four-read pilot is not the final write deliverable.

Live migration/client versions, form creation defaults and renderer snapshot
semantics remain implementation-time checks with owners in 3B/3C. No runtime
incident, migration application, performance gain or production readiness is
claimed by this source-backed plan. Ship corrected backend contracts before
enabling corresponding tools; disable tool exposure on rollback, never restore
the unsafe writer or erase receipts/queued commitments.
