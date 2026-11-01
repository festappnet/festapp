# Seating transition for existing admissions

Date: 2026-10-31
Status: Implemented and validated locally on 2026-11-01; production not deployed
Verification: standard (authorization, commercial identity, inventory, concurrency)
Architecture and UI/UX review: `gpt-6-astra`, `medium`, 2026-11-01; findings integrated below.
Authority: this document supersedes the earlier prepare-or-cancel prototype and
previous versions of this plan. The execution prompt points here.

## 1. Product decision and scope

The organizer can enable the seating editor immediately on an existing event.
Enabling editing does not change the public admission mode. A persistent worklist
then supports preparation and assignment of existing admissions. Organizer-managed
seating is a complete, long-lived operating mode. Public seat selection is a
separate optional configuration change, never the required last step of seating.
A notice is the entry into this process, not its entire implementation.

The user chose organizer assignment now. The same domain operation must later
support participant assignment through a restricted authorization adapter.
Participant authentication links, notifications, automatic allocation and a
seating-aware waitlist after publication are excluded from this implementation.
Do not create dormant participant permissions, token formats or public routes.

Preserve purchased rights: no cancellation, new order, new ticket/QR, price change,
payment change or promotion from the waitlist is implicit in this transition.
Do not publish the current uncommitted prototype migration or dialog.

### Observable journey

1. **Enable editing.** Save the feature. Safely detach any previously inactive
   public binding in the same transaction. If a compatible source and target are
   unambiguous, create/resume their organizer-managed configuration. Otherwise
   show Choose a plan or Repair this plan; do not create a dummy transition or
   fail feature enabling. Show the notice once after this successful change.
2. **Prepare the plan.** Edit and explicitly save geometry, products and standing
   areas. A persistent workspace summary shows the current seating work and its action;
   it can also show the successful All assigned state.
3. **Seat existing admissions.** Select real tickets and compatible saved seats,
   review exact mappings and commit. Unpaid ordinary orders reserve an admission
   just as they do today. They must not disappear from the worklist.
4. **Continue operating normally.** Waiting people and live offers are separate
   categories. Existing offers keep their deadlines and old acceptance behavior.
   An accepted offer adds its stable tickets to the assignment worklist, including
   when the existing acceptance owner splits the order.
5. **Optionally start public seat selection.** This is a separate action, not a
   required final wizard step. Review the affected forms, availability, limits and
   new sales mode. The server rechecks the complete cohort and commits publication
   atomically. Failure leaves the original sales mode intact and shows actionable
   reasons. Success does not open a manually closed/scheduled-closed form.

Suggested Czech notice, localized through the existing string owner:
"Plánek je připravený k úpravám. Stávajícím přihláškám je potřeba doplnit místa.
Přihlašování zatím funguje beze změny."
The persistent banner has actions "Přiřadit místa", "Čekací listina" and a separate configuration action,
when permitted, "Spustit výběr míst pro nové přihlášky". Never show an enabled action
whose only result is an unsupported-operation exception.

The original case has a concrete successful outcome: assign the nine admitted
tickets and show "Místa jsou přiřazena. Přihlašování a čekací listina fungují
beze změny." Show "1 na čekací listině" separately as information with the
normal waitlist action, not as a red failure to finish seating. If that person
accepts a valid offer later, show one new unassigned admission. Public-selection
readiness can remain unavailable without invalidating this operating mode.

## 2. Repository evidence and corrections to the earlier plan

| Confirmed fact | Source | Required decision |
|---|---|---|
| The original occasion save checked a fictitious blueprint on every form and auto-attached one form. The working tree contains an uncommitted alternative. | `database/functions/others/update_occasion.sql`, `update_occasion_internal_v1`; compare HEAD with working tree | Replace both automatic activation and the prototype confirmation flag with a persisted preparation lifecycle. |
| An enabled attached blueprint takes priority over ordinary registration capacity. | `database/functions/eshop_waitlist/form_capacity.sql`, `get_form_registration_mode_internal` | During preparation `forms.blueprint` must not activate the target sales plan. Keeping the numeric capacity alone is insufficient. |
| Capacity counts distinct ticket IDs through OPT/order links and excludes waitlisted/cancelled states. | `get_form_capacity_snapshot_internal`, same file | Derive work from real admissions. Do not add a person ledger or authoritative cached counters. |
| Addressed seats reference a specific `eshop.order_product_ticket` row, not just a ticket. | `database/tables/tables.sql`, `eshop.spots` | Mapping identifies the exact purchased admission item and validates its ticket/order/form ownership. |
| Existing replacement cancels/prepares and creates an order. Existing swap refreshes product JSON from the current catalog and can alter price/payment. | `blueprint/apply_seat_order_internal.sql`; `eshop/swap_spot_tickets.sql`, `_swap_spots_update_ticket` | Neither is a safe implementation of pure backfill, even when the product ID is unchanged. |
| Generic inventory allocation selects a free spot by context and does not exclude plan seats; cleanup distinguishes blueprint behavior by the occasion feature flag. | `inventory/apply_allocations.sql`, `apply_allocations` | Preparation must not allow an ordinary order update to auto-claim or erase a manually assigned plan seat. Audit allocation and cleanup together. |
| Existing email rendering enriches historical ticket JSON with live seating without rewriting its commercial snapshot. | `eshop/order_seating.sql`, `order_tickets_with_seating_internal`; `eshop/get_order_details_for_email.sql` | Prefer existing placement enrichment; do not rebuild order products from current prices to display the new seat. |
| The batch-print guard rejects changes for any noncancelled batch ticket. Generic mutable-ticket checks also reject stock/waitlisted/preparing-payment orders, but do not themselves reject used tickets. | `eshop_ticket_batches/guards.sql`; `eshop_orders/check_order_is_mutable.sql` | Eligibility needs explicit placement rules; neither an empty seat nor one generic guard proves eligibility. |
| A public blueprint offers its bound products independently of ordinary form fields. | `blueprint/availability.sql`, `blueprint_form_products_internal` | Publication can change the offered catalog and effective capacity. Preview that change explicitly and check all dependent forms. |
| An ordinary primary product can currently pass materialization without a selected seat through a visible form field. | `eshop/materialize_ticket_products_internal_v1.sql`, product-scope condition | Publication also needs a server-side addressed-admission requirement; a stale or direct caller must not create new seatless admissions. |
| Admin editor currently picks the first blueprint by occasion, and includes only tickets already attached to its seats. | `eshop/get_blueprint_for_edit.sql` | Transition context must explicitly identify its blueprint and load unassigned admissions; this reader alone cannot supply the worklist. |
| Waitlist acceptance can split orders and uses the same stable tickets. | `eshop_waitlist/accept_offer.sql`, `accept_waitlist_offer_internal` | Do not freeze the worklist by original order ID or infer admission from an offer alone. |
| The shared assignment lock helper discovers order parents from currently occupied seats. | `inventory/lock_spot_assignment_scope_internal_v1.sql` | An empty destination does not lock the source admission. Explicitly add source orders/items to the same lock owner before children. |
| Form authoring and occasion saves lock forms/products but their present wrappers do not both take the blueprint occasion scope first. | `eshop_forms/update_form_client_sync_v1.sql`; `others/save_occasion_domain_command_internal_v1.sql` | Audit and align affected entrypoint lock ordering; never acquire the advisory scope late from a guard holding a form/product lock. |

Paths above are relative to `database/functions/` unless otherwise qualified.
The earlier 14 Flutter tests and four SQL files cover the prototype, not this
specification. No new behavior is claimed from those passing tests.

## 3. State and persistence

### Three different facts

- `occasions.features.blueprint`: whether editing/management is enabled.
- An organizer-managed seating configuration: target plan and current assignment
  work for a form, valid indefinitely without public seat selection.
- `forms.blueprint`: the only active binding used by public seat sales.

Do not make the feature toggle a second active-sales selector. Do not introduce
`isReady`, cached `missingSeats`, a second ticket list or an additional seat hold.

Add `public.form_seating_transitions` with:

| Field | Meaning |
|---|---|
| `id uuid` | Stable transition identity; commands/replays refer to this ID, not only a form ID. |
| `occasion bigint` | Stored verified scope for authorization/audit, including terminal configurations whose parent form/plan was later legitimately deleted. |
| `form bigint`, `blueprint bigint` | Required source and target for organizer-managed configurations, verified against their common occasion and organization. |
| `state` | `organizer_managed`, `published` or `cancelled`. Organizer-managed is a usable mode, not an unfinished failure. No stored `ready` state; assignment coverage and optional publication readiness are separate current projections. |
| `revision bigint` | Incremented for explicit transition edits, assignment changes and finalization. It does not pretend to version all external admissions/inventory. |
| `started_by`, `started_at`, `finished_by`, `finished_at` | Verified actor and database time; terminal provenance. |

Use a partial unique index on `form WHERE state='organizer_managed'`, foreign keys,
CHECKs, RLS and command-only grants. Preserve terminal rows for audit/replay.
No direct authenticated table writes or application triggers. Deleting an
occasion uses its existing explicit deletion owner to remove dependent rows;
ordinary form/blueprint deletion is blocked while an organizer-managed configuration
references it or live sales/placements require it. After legitimate cancellation
or final detachment through the existing owners, terminal parent references may
be set NULL by `ON DELETE SET NULL`. A CHECK requires both references in
`organizer_managed` state. Preserve original source/target IDs in the existing
private command audit/receipt; terminal records retain the stored occasion and
lifecycle provenance. Do not permanently prevent an otherwise authorized parent
deletion merely because a cancelled intention once referenced it.
Copies create fresh sales configuration, never copy transition rows, assignments,
receipts, holds or actor identities.

### Legal transitions and cancellation

| From | Action | Result and preconditions |
|---|---|---|
| Editor enabled, no usable target | Choose/create/repair target | Configuration UI state only; no incomplete transition row. Original public mode remains. |
| No active configuration, valid source/target | Start/resume | `organizer_managed`; repeated save resumes the same configuration without duplicates. |
| `organizer_managed` | Assign/release | Remains `organizer_managed`, with original admission and commercial facts preserved. |
| `organizer_managed` | All current admissions covered | Remains a complete usable mode; show All assigned independently of waiting/offers. New admissions can legitimately add work later. |
| `organizer_managed` | Back/close, or decide not to publish | No domain mutation and no requirement to release placements. Resume at any time. |
| `organizer_managed` | Explicitly remove seating configuration | `cancelled` only when it owns no remaining placements and target has no conflicting hold/use. Original regular mode remains; never reactivate an inactive source binding. |
| `organizer_managed` | Optional publish cohort | All cohort rows become `published` together, after section 8 checks. |
| `published`/`cancelled` | Retry same command | Return its original authorized receipt. Never reopen the transition. |
| Terminal transition | Start another | New transition UUID; no reuse of old revisions or command identities. |

Leaving the workspace or abandoning the intention to offer public selection is
not cancelling seating. Organizer-managed mode remains valid and needs no cleanup.
There is no one-click rollback that silently releases seats already assigned to
paid admissions. When placements exist, offer Continue or an explicit reviewed
release through the assignment operation first. Used or batch-printed placement
protection may prevent release; cancellation must not override it.

Disabling the occasion feature cannot bypass these rules. If only empty
preparations exist, cancelling them and disabling can be one explicit command.
If placements or published seat sales exist, reject the generic toggle with
an actionable reason. Reversal after live seat sales is outside this release;
retain the current valid active binding until an independently validated reversal.
Do not fall back to unlimited regular admission because the feature was hidden.

### Choosing a target and shared plans

Never silently switch to the lowest blueprint ID. The context names the selected
target. Extend the admin reader with an explicit, scoped blueprint ID through
the normal transport; occasion-only routing may select the sole unambiguous plan.
Multiple possible plans require a visible selection. Retained schema-1 plans
require the existing reviewed conversion/repair path; no automatic lossy reset.
Enabling editing still succeeds and exposes the repair reason.

The enabling command records previous feature state and inactive binding IDs in
its existing private configuration audit/receipt before changing them. When a
retained `forms.blueprint` was inactive only because the feature was disabled,
detach it in the SAME transaction that enables the feature, preserving its plan
and existing seat associations. Create/resume a configuration only if a valid
source/target is identified. If target selection or legacy repair is outstanding,
retain provenance in that command audit, leave the source in its old public mode
and show configuration work without a nonnull-target placeholder row. Do not detach an already active seating form.
Cancelling preparation never restores an old inactive binding while the feature
is enabled; that would activate sales without publication. New empty forms and
unlimited occupied forms follow the same explicit-publication rule. When no form
exists, enable editing without a fictitious transition; creating/selecting a
source form later starts the actual scoped preparation. Before a configuration
exists, Choose/Repair status and permitted plan metadata come from the ordinary
authorized occasion/form configuration response, not a fake transition ID or a
private holder worklist. A valid target means the correct owner/scope and supported
canonical document; a saved empty plan can be a valid target before supply is
ready. Product/supply compatibility then governs assignment, not feature enabling.

A target cohort is all `organizer_managed` configurations using one blueprint.
The same cohort is the assignment scope and the optional publication cohort.
The server derives membership, while the preview returns its exact sorted IDs.
Publish the whole cohort atomically, not form A while form B still accumulates
unseated claims to the same physical seats. Adding/removing a member invalidates
the preview. Detect other ordinary forms exposing the same admission products;
show `UNCOVERED_ADMISSION_SOURCE` as an OPTIONAL PUBLICATION blocker until the
organizer includes them or removes that offering through normal form authoring.
It is not a blocker for assigning authorized existing admissions in the current
organizer-managed cohort; those assignments still enforce their exact per-item
inventory, entitlement and atomic-unit checks. Include editor-created orders in
those forms; scope is not just public checkout.

For the first release, reject a new retrofit targeting a blueprint that is
already publicly live through another form (`TARGET_ALREADY_PUBLIC`). Do not
add unseated obligations behind a live seating catalog. Existing active seating
forms remain usable and are not migrated again just because settings are saved.
Selecting a separate unused target is supported; retrofitting onto a live shared
hall needs a separately designed maintenance/obligation-reservation mechanism.

## 4. Admission classification and coverage

One canonical SQL projection supplies the summary, paginated worklist, preview
and commit validation. It joins actual ticket/OPT/order/form facts under the
transition scope. The base identity is an admission OPT plus its ticket, not a
name, email, order count or invented participant record.

Find primary admission items through the existing form primary-product/`spot`
type semantics (`eshop_forms/primary_product_guard.sql`). Ignore food/taxi/other
add-ons. Classify inconsistent legacy data visibly, not by picking the first OPT.

| Category | First-release behavior |
|---|---|
| Normal admitted ticket on a mutable order, no assigned seat | Assignable, including ordinary unpaid tickets. |
| One valid target seat already assigned | Covered. Do not demand a second seat. |
| Valid standing admission | Covered by its existing product/PIC allocation and a matching saved target area; no fabricated numbered seat. |
| Waiting ticket | Never assignable; remains in existing FIFO/waitlist workflow. |
| Live offered place | Not a seat assignment; offer remains valid until acceptance, rejection or expiry. |
| Accepted offer | Classify from resulting current ticket/OPT ownership. Add to ordinary admission work, including partial acceptance. |
| Cancelled ticket/order | Excluded; existing cancellation owner releases its allocations. |
| `preparing_payment` order | Publication blocker until the existing payment owner settles/fails/cancels it. Never alter a provider session. |
| Unsold stock/batch ticket | Not an admitted person; never import it as a seated customer. Existing inventory consumption still counts. |
| Used ticket with an existing valid target placement | Covered, placement immutable through this workflow. |
| Used ticket without placement or with a different target | Nonassignable blocker in this release. Do not un-use it or guess a seat. Preparation can remain open or be cancelled if it has no placements. |
| Noncancelled batch-printed ticket needing placement change | Nonassignable `BATCH_TICKET_PRINT_IMMUTABLE` blocker. Never alter or invalidate printed artifacts implicitly. |
| Missing primary item, multiple candidate admission items, cross-form ownership, ambiguous historical product JSON | `ADMISSION_DATA_AMBIGUOUS`; excluded from mutation and blocks publication, with a diagnostic reference for supported repair. |
| Admission already assigned to a different blueprint | `ADMISSION_ASSIGNED_ELSEWHERE`; require the existing explicit commercial relocation workflow. |

For product modes, a target admission product is addressed OR standing. A product
bound to both seat bindings and a capacity area is ambiguous for legacy admission
backfill and blocks this transition (`PLACEMENT_MODE_AMBIGUOUS`). For future sales, distinct product variants can remove the catalog ambiguity,
but creating variants does NOT repair already purchased ambiguous admissions.
Their historic entitlement needs a separately reviewed commercial/repair path;
never silently relabel a purchase or advertise catalog creation as a one-click
fix for historical ownership.

For a standing product, publication requires that its purchased PIC quantities
already map to the selected saved area and that the canonical inventory owner
confirms sufficient allocation. A missing standing allocation is a blocker,
not an invitation to create duplicate capacity. Before any assignment exercise,
show a compatibility checklist pairing each purchased admission product with its
saved target seats or standing area/context. Binding an area to the SAME existing
legitimate product/context can establish coverage of already valid standing
allocations through normal area authoring. Missing allocations route to the
existing inventory editor/diagnostic with the concrete product/context; ambiguity
without a supported safe repair exposes a diagnostic reference instead of a
fictional repair button. The first release does not add a second standing-
assignment UI or reinterpret a seated admission as standing.

Display counts in mutually exclusive primary categories: unassigned addressed,
assigned addressed, covered standing, blocked admitted, waiting and offered.
Use the existing effective waitlist lifecycle for category precedence; offered
people are not counted again as ordinary waiting. Counts are ticket/admission
counts, not number of orders or number of accessory allocations. The complete
server query determines publication, regardless of filters or page size.

## 5. Module interface, permission seam and future participant adapter

The Festapp seat-assignment module sits next to existing blueprint operations.
It operates on already purchased admissions. Order creation, financial
replacement and cross-price swaps retain their distinct existing contracts.

Proposed public operations (names are new, not existing RPC claims):

| Operation | Request | Response and effect |
|---|---|---|
| `get_seating_transition_context` | Entry transition ID; bounded search/filter/cursor | Resolve the target cohort server-side; return capability-filtered aggregate and/or private context. No mutation or global customer list. |
| `preview_ticket_seat_assignment` | Entry transition ID, explicit item-to-seat mappings | Resolve authorized member forms of its target cohort; return exact cross-form effect, touched-transition revision bundle/fingerprint or blockers. |
| `set_ticket_seat_assignments` | Same mappings, expected fingerprint/revisions, command UUID | Atomic set/move/release across authorized cohort members; full before/after atomic-unit closure, committed receipt and refreshed projections. |
| `preview_seating_publication` | Transition ID | Exact cohort, old/new sales configuration, catalog/capacity effect, current readiness and fingerprint. |
| `publish_seating_transitions` | Exact cohort IDs, expected fingerprint/revisions, command UUID | One atomic publication or no change with typed blockers/conflict. |
| `cancel_seating_configuration` | Transition ID, expected revision, command UUID | Terminal cancellation only with no remaining placements; no commercial rollback. |

Start/resume is a private domain operation of the authorized occasion/form
configuration command, with its existing receipt. A separate typed start action
is needed only for explicit target selection/new forms after initial enable;
it must call that same owner, not duplicate activation logic.

A mapping contains `ticketId`, `admissionItemId`, `expectedSpotId` (nullable) and
`targetSpotId` (nullable for release). Validate the item belongs to this ticket's
current order and an authorized source form in the entry transition's target
cohort. An entry transition is a scoped lookup handle, not a single-form batch
restriction. Mixed-form couch mappings are allowed when all member admissions
and complete before/after unit closures are authorized. Return the source form
on each review row. Require unique item IDs and unique nonnull target spots.
Reject duplicate/unknown fields, mixed occasions,
empty no-op batches and payloads exceeding existing order-mutation item limits.
The first release permits only unambiguous single-admission tickets, while the
item-based protocol can represent future multi-admission tickets without a new
identity scheme. The source identity and original product are server-derived.

### Authorization matrix

Use typed predicates under `database/functions/user_permissions/`, composed from
existing operation rules, not client flags or a new independent role system.

| Capability | Required existing authority |
|---|---|
| Enable feature | Existing occasion-settings authority (`can_edit_occasion`). Do not additionally require order-editor membership just to enable editing. |
| Read aggregate seating status | Form-authoring authority OR order-read authority grants a usable scoped context. Configuration-only readers get safe totals, not holder rows. |
| Choose/change target / optional publish / remove configuration | Existing form-authoring authority for every affected form; derive scope from stored rows. |
| Read holder worklist and exact mappings | Existing order-read authority grants the assignment context independently of form-authoring permission, with capabilities for permitted mutations. |
| Assign/release | Existing order-write authority AND authorized access to the exact ticket context. Do not assume that write membership implies private order-read membership; an order operator with both order permissions must not additionally need form-authoring rights. |
| Edit geometry/catalog | Existing blueprint/catalog authority. This does not itself grant access to customer details. |
| Future participant | Denied today. Later adapter resolves a verified ticket-scoped grant and calls the same eligibility/transaction implementation. |

Authorize before private context, before mutation and before receipt replay.
Permission revocation must also be respected after lock waits. Test the actual
snapshot/volatility behavior with two connections; do not assert that calling a
STABLE predicate twice automatically observes a newly revoked membership.

An order-only operator can enter and use a previously configured target without
being able to choose or publish it. A configuration-only editor can see safe
status but not holder rows. When another capability is needed, show which access
is missing and leave the work resumable by an appropriately authorized organizer;
do not require a notification service or combine unrelated roles globally.

Separate the private verified-scope resolver from the placement implementation.
Public requests never supply an actor ID, role, `asAdmin` or arbitrary authorized
scope. The future participant adapter will return only that subject's admissions
and sanitized availability, not reuse the organizer's customer context. It can
use existing holds via `select_spot`; no new hold table. Do not add abstract
transport scaffolding or hypothetical credential infrastructure before that adapter
exists. Define the seam and test its scope, not a dormant public implementation.

### Preview and mutation semantics

Previews do not reserve. Return the target blueprint/layout revision, transition
revision, relevant form/config versions and all touched-transition revisions, exact
before/after mapping including source-form IDs, immutable commercial item identity and a SHA-256 semantic fingerprint. Relevant seat state,
hold identity/expiry, atomic unit membership, allocation parents and original
commercial snapshots contribute to the fingerprint. Do not hash changing server
clock text or unrelated customers' assignments into it.

Assignment preview covers every touched member and atomic closure, not unrelated
cohort admissions; adding unrelated assignment work must not discard a valid
pair draft. Commit still re-resolves membership and per-item authorization.
For publication, fingerprint the entire cohort, relevant source-form configuration,
full admission/offer coverage and catalog/capacity effect, not just a summary
count. Two different ticket sets of the same size are different previews.

On commit acquire locks, recompute current semantics and compare. A stale preview
returns `CONTEXT_CHANGED` and refreshed reasons; the UI retains mapping intent
but requires another review. No read-before-write rebasing. Changing product
price after preview does not reprice a purchased admission; it can invalidate
new-sales publication details. An unrelated ordinary receipt/audit row must not
invalidate an otherwise unchanged assignment.

## 6. Placement, finance, presentation and inventory invariants

### Preserve commercial facts exactly

Pure assignment changes only physical placement associations, transition version,
normal update metadata, audit/receipt and sync invalidation. It preserves order,
OPT and ticket IDs, order symbol/sequence, ticket symbol/QR, all admission states,
purchased product ID/quantity, original product/price/currency snapshots,
order total, payment recipient/method/amount/paid/deadline/deposit, financial
history and original answers. An issued Stripe session/intent is not recreated.

A catalog price change is not grounds to charge a difference for assigning the
same purchased product. Do not call `_swap_spots_update_ticket`, `_swap_spots_generate_product_json`,
`replace_blueprint_order_command_internal`, order materialization or finalization
for this operation. Same-product compatibility is necessary but not sufficient:
verify physical/resource context and all purchased admission quantities as well.

Read seating through `order_tickets_with_seating_internal` and
`order_spot_metadata_internal`, preserving historical JSON. Bring admin order
rows, customer order display, refreshed ticket/PDF data and email rendering to
that same projection at their existing data owners. Do not patch seat labels in
Flutter as a separate truth. Adding a seat does not automatically send email or
regenerate/revoke existing documents. A previously downloaded ordinary PDF keeps
its QR validity; a fresh authorized download includes current placement. The UI
states that an older downloaded file will not update itself. Any explicit resend
uses the existing email queue and opt-in follow-up behavior.

### One allocation for an already purchased entitlement

`eshop.spots.order_product_ticket` remains the physical assignment authority.
Do not add a second placement table. Ignore accessory spots when determining
numbered admission coverage. A changed mapping updates all relevant physical
associations in the same transaction, including exact release of a previous
compatible placement. Target seats must be saved canonical bindings, have the
same purchased product, be available/unblocked, be in the correct target and
have no conflicting active hold. Never evict another customer or release an
entire group as an implicit side effect.

Atomic seat units are mapped completely in one command. If a two-seat couch is
chosen, preview requires two explicit eligible admissions for its two seats; do
not clone one ticket or invent a second purchased entitlement. Moving/releasing
also respects the complete before-unit closure and used/print protection.

Product maximum and PIC capacity already include the source purchase. Assignment
must not demand another admission or count its OPT again. Do not call the normal
new-buyer hold preflight, which checks a positive purchase quantity. With a
contextless addressed seat, retain legitimate ancillary/PIC allocations. If a
seat itself fulfills a required PIC/resource slot, exchange the prior physical
allocation through the inventory owner and validate the post-change totals; do
not keep both allocations or release unrelated food/taxi/resource entitlements.
A failed post-allocation check rolls back the entire command.

Extend `apply_allocations` so generic allocation cannot choose a free canonical
addressed seat merely because it shares a context with a regular order. Count an
explicitly bound addressed seat when it legitimately fulfills that context;
exclude such seats from arbitrary free-stock selection. Reconciliation/cleanup
must retain a valid explicit placement during preparation regardless of whether
`forms.blueprint` is active yet. Validate paid/unpaid updates, payment callbacks,
product edits and cancellation after assignment, not only the assignment command.

### Prevent later bypasses

After publication, the ordinary order materializer requires an explicit selected
seat for an addressed admission product. A visible primary product field, editor
privilege, old browser payload or a direct RPC must not create a seatless admitted
ticket. Standing products retain their existing quantity/allocation path.
All callers, including batch creation, editor creation, accepted waitlist offers
and replacement, must encounter the same domain rule where applicable. Pending
waiting/offers cannot straddle publication, so no exception for an old offer is
needed after successful cutover. This constraint is not limited to forms present
in the publication preview: creating/copying/reopening another regular source or
adding the same addressed-only admission SKU to it must not restore a seatless
emitter afterward. Validate those source-authoring changes AND resolve active
published admission obligations in the materializer. Return
`ADMISSION_SOURCE_REQUIRES_SEATING` for an incompatible ordinary source; a form
explicitly using the same published plan continues through its seat-selection
path. Closed configuration drafts may be retained, but cannot admit orders
through editor/direct/provider callers without the same validation.

Generic form save cannot attach/detach a target plan or change admission mode
around an organizer-managed configuration. Route such changes through the publication or
cancel owner with the same checks. Geometry/product edits cannot delete,
reproduct or block assigned seats, delete referenced transitions or move their
physical resources to another scope. Retain existing protected-seat behavior and
invalidate affected previews; do not freeze the whole editor unnecessarily.

## 7. Transaction and retry protocol

For each new mutation:

1. Validate bounded syntax and resolve stored occasion, transition, source orders,
   admission items, target/before seats and affected source forms. Authorize scope
   before exposing private facts. Derive the full atomic/resource closure.
2. Acquire `lock_blueprint_scope_internal` for sorted occasions before any form,
   product, inventory or seat lock. New operations are single-occasion. This is
   the shared rendezvous with geometry, hold, swap, cancellation and offer owners.
3. Claim the existing actor/UUID/payload-bound mutation receipt. An exact replay
   still requires current scope authorization. Never execute another mutation
   because a previous receipt could not be fetched.
4. Lock sorted source/cohort forms, transition rows and source orders before
   products/blueprints/pools/contexts/resources/slots/spots/tickets. Extend the
   shared lock owner to include explicit source order/item IDs: discovering parents
   only from empty destination seats is insufficient. Do not acquire a parent
   after a child by invoking a generic mutable-ticket check late.
5. Reread ownership, states, immutable-print facts, actual holder permissions,
   expected associations, hold expiry using database time after waits and all
   version/fingerprint inputs. On changed resource parents retry the same frozen
   command under the repository's serialization policy, not an updated payload.
6. Apply exact placements and inventory reconciliation, enforce all invariants,
   bump the correct aggregates, record private audit/history and complete the
   existing sync/receipt owner in the same transaction.

Move the affected form and occasion save wrappers to take the same advisory
scope before their first form/product lock. Check receipt/scope ordering against
existing writer callers so the change does not introduce opposite-order waits.
Do not take a new advisory lock from inside `check_form_capacity_settings_internal`
after its caller already owns form locks. Keep compatibility adapters on this
one validated domain owner, not a temporary trigger.

Cancellation, seat holds, layout save, inventory edits, order-product mutation,
payment completion, waitlist acceptance and scan/use can all invalidate preview.
The writer rechecks relevant facts after locks; a transaction that loses the race
fails without partial effects. In particular, a source ticket cancelled while
waiting cannot receive a seat, and an expired hold cannot remain a blocker solely
because preview used an earlier timestamp.

Use the existing `ClientCommandTransport`/receipt conventions. Freeze the exact
payload and command UUID across timeout, network failure, app restart recovery
where the transport supports durable intent, and serialization retries. If a
request may have committed, show Recovering and prevent another independent
submit until replay determines its outcome. A terminal rejection followed by a
new reviewed mapping gets a new command UUID. Duplicate clicks share one flight.
Do not show success, move the next ticket or publish local selection before the
committed receipt. Record operator and changed IDs, not sensitive holder data,
in general audit labels or public sync payloads.

## 8. Publication contract and capacity changes

Publication is an explicit configuration operation, not a side effect of the
last assignment. Derive and lock every organizer-managed form in the target cohort,
plus dependent admission sources. Check their current facts, not a frozen list
of tickets from transition creation. Admit new tickets during preparation under
the original capacity rules; the summary can legitimately grow. Offer the
existing manual form pause as an optional organizer action, never pause silently.

Reject publication with concrete current blockers if any of the following holds:

- Unassigned or blocked admitted tickets, a foreign placement, missing/ambiguous
  primary admission item or invalid standing coverage.
- Effective waiting tickets, live offered places or unsettled payment preparation.
  Expire stale offers through the existing lifecycle owner before classifying.
- An uncovered ordinary admission source, already-live shared target or changed
  cohort/source form/blueprint since preview. A target product already promising
  addressed admissions through another live blueprint cannot be independently
  claimed by this retrofit; report the exact conflicting source instead of
  inferring which hall an old admission belongs to.
- Invalid/unsaved schema/resources, missing admission products/prices for future
  sales, no usable placement supply, broken bindings or insufficient shared PIC
  supply. Fully allocated but otherwise valid supply may publish as sold out;
  lack of free seats alone is not a failure.
- Conflicting active holds, print/used restrictions on an actual requested change,
  or a concurrent commercial/physical mutation invalidating reviewed facts.

Before confirmation show each source form's original participant cap and the
new effective seat/standing catalog and availability. Removing a cap of 10 in a
hall of 100 can expand future sales; it is not a cosmetic field cleanup. The
organizer confirms this exact new scope. Do not silently alter product maximums,
standing stock, shared pools or a preexisting per-product ceiling to make the
numbers match. Reuse canonical availability owners, not a seat-count estimate.

On successful publication, in one receipt transaction:

- Attach the exact saved blueprint to all cohort forms.
- Set participant capacity to NULL, waitlist enabled to false and waitlist offer
  duration to NULL; preserve historical waitlist rows and terminal offers.
- Preserve form open/closed state, schedule, links, pricing, payment configuration,
  questions, existing responses and feature configuration unrelated to seating.
- Increment form/capacity/transition aggregate versions, mark the transition rows
  published, and invalidate the correct public and private sync projections.

The form row locks make finalization linearizable with ordinary checkout,
provider completion and accepted offers. If an admission commits first, final
coverage must include it. If publication commits first, the next writer observes
the published requirement for a selected addressed seat. A cached old browser
receives a typed mode-changed response, reloads authoritative context and retains
safe customer text locally; it is never accepted as an unseated backdoor sale.

Organizer-managed seating is successful and usable with a live waitlist. Waiting
and offered counts do not make its overall status red or its committed placements
incomplete. They affect only readiness of the separate public-selection action.
The first release deliberately does not transfer a live waitlist into a new seat
reservation mechanism. The organizer can continue preparation/assignment while
waiting/offers resolve normally, or cancel an empty preparation. Do not suggest
cancelling paying customers or emptying a queue merely to dismiss a technical
error. A long-lived queue can delay optional public selection indefinitely; this must
be clear in that action's detail, while organizer-managed seating continues as
the normal successful outcome. Do not frame resolving/cancelling the queue as a
requirement to finish assigning existing admissions.

## 9. UI behavior, scale and recovery

Keep the generic venue package responsible only for geometry/rendering/selection.
All customer worklist, capabilities and commands live in Festapp. No Supabase
models, customer PII or role checks enter `vendor/blueprint`.

- Persistent summary distinguishes waiting, offered, admitted and blocked, with
  counts and links. Show aggregate status even to configuration editors without
  holder-read permission; private rows require their own authority.
- Use explicit plan/form scope and stable keys. Existing names may be absent;
  show ticket/order identifiers. Never treat shared customer email as identity.
- Search by available holder fields/order/ticket identifiers. Use server-side
  filtering and bounded cursor pagination (default 50, maximum 200), with counts
  derived for the whole scope. No full-event PII export on page load.
- Use one saved-plan seating workspace with a ticket queue. The primary flow is:
  select one admission, highlight compatible available seats, click a seat, and
  review the exact proposed pair in a compact panel. For deliberate batches show
  explicit pair rows, source form and holder/ticket identity; do not infer pairing
  from selection order or guess the best seat. Clicking a couch first requests
  its full number of eligible admissions, including across authorized member
  forms, before enabling confirmation. Provide a keyboard-accessible compatible
  seat list alongside the canvas. Local pair drafts are neither a hold nor a
  committed assignment.
- Unsaved geometry presents Save / Discard / Cancel before assignment or optional
  publication. Cancel returns to the unchanged layout draft. Do not autosave,
  silently discard or trap the user into choosing Save/Discard.
- Refresh after a committed mapping preserves search/page and advances only to
  the next still-eligible item. Newly accepted offers appear on refresh; show
  that the worklist changed. A stale row is removed/updated after context reload.
- Distinct empty states cover no admissions yet, all admitted people assigned,
  no search results and no compatible saved seats. All assigned is a success
  state even when a separate waiting/offered chip is nonzero. No compatible seats
  leads to the product/supply compatibility checklist before more pairing work.
- Distinguish loading context, committing a known request and recovering an
  uncertain outcome. After a conflict retain queue position and nonconflicting
  draft pairs, mark invalid pairs, refresh context and require a new exact review.
  Do not throw away an entire batch or silently resubmit with refreshed semantics.
- An admitted ticket without sufficient compatible seat supply remains admitted.
  Show the concrete product/supply shortfall, including when a valid offer adds
  work later. Do not promise a numbered seat to a waiting person or block their
  already valid offer acceptance to conceal a short plan.
- Errors name the ticket/seat and available next action when authorized. Do not
  display SQL, raw PostgREST payloads, hold secrets or hidden customer notes.
- Keyboard/Escape closes review without mutation; duplicate submit is disabled;
  mobile layout keeps the reviewed mapping and action readable without horizontal
  whole-event tables. Use current dialogs and formal Czech copy.

Error taxonomy: `CONTEXT_CHANGED`, `SEAT_UNAVAILABLE`, `HOLD_ACTIVE`,
`ATOMIC_UNIT_INCOMPLETE`, `PRODUCT_MISMATCH`, `PLACEMENT_MODE_AMBIGUOUS`,
`INVENTORY_CONFLICT`, `ADMISSION_DATA_AMBIGUOUS`, `ADMISSION_ASSIGNED_ELSEWHERE`,
`USED_TICKET_PROTECTED`, existing `BATCH_TICKET_PRINT_IMMUTABLE`,
`WAITLIST_PENDING`, `OFFERS_PENDING`, `PAYMENT_PENDING`, `UNCOVERED_ADMISSION_SOURCE`,
`TARGET_ALREADY_PUBLIC`, `ADMISSION_SOURCE_REQUIRES_SEATING`,
`ASSIGNMENTS_EXIST`, `MODE_CHANGED`.
These are proposed new stable reason codes except the explicitly existing batch
code. Preserve existing code owners/adapters where an equivalent already exists.
Unauthorized callers get the normal scoped denial without distinguishing
whether a foreign ticket or transition exists.

## 10. Implementation waves and exact completion gates

### Efficient execution protocol

This section governs HOW the already specified work is executed. It does not
reduce scope, verification depth or any financial/authorization/production guard.
A request to review or improve this plan/prompt is planning only. Start application
implementation only when the user explicitly starts execution. No worker should
be resumed merely because the execution prompt is being edited.

**One focused start, then implementation.** Read the authoritative plan once.
Inspect the current dirty diff and only the named owners needed to confirm its
premises. Reuse the source evidence and Astra review above; do not repeat a broad
architecture survey, start another design interview or launch another independent
audit. Update only material premises invalidated by the actual checkout. Record
unrelated dirty paths and allocate exclusive write ownership before edits.

**Freeze one small contract before parallel coding.** The primary owner writes
one compact companion contract under `docs/plans/` containing actual SQL/RPC
names/parameters, JSON/receipt envelopes, capabilities, reason codes, pagination,
mapping/publication examples, and the saved-plan UI integration seam. Resolve
these from sections 3-8 in the initial backend pass; do not defer naming/schema
choices to each caller. This artifact is a coordination specification, not a new
runtime schema or code generator. Astra may inspect the UI and design interaction
while this is being finalized; start its integration coding once the interface
is frozen. The SQL implementation can then finish against that same contract.
A contract change requires a concise owner-to-owner message identifying affected
callers/tests BEFORE editing it; no silent mismatches or fallback JSON adapters.

| Execution stage | Primary owner | Astra medium UI/UX owner | Exit/evidence |
|---|---|---|---|
| Focused start | Inspect dirty state, choose exact checks, establish source/RPC contract and one failing reproduction. | Read existing UI seams and prepare the interaction/file scope; do not edit shared integration files yet. | Exact owned files, frozen contract and red-capable real SQL case. |
| Parallel implementation | Implement waves 1-2 and the backend part of wave 4 in coherent batches. | Implement wave 3 and publication interaction against the frozen contract, including scoped model/transport/tests. | Backend and UI independently match the same contract; no placeholders accepted as final behavior. |
| Integration | Finish shared callers, projection/guard coverage and migration assembly; review the actual UI/backend seam. | Finish role/empty/conflict/recovery states and resolve observed UI issues. | Actual typed UI calls real disposable SQL, including the nine-admitted/one-waiting outcome. |
| Final targeted checks | Run final SQL/concurrency/migration checks on final SQL inputs. Coordinate the single Flutter slot. | Run its final affected Dart/Flutter checks once the UI inputs are final, or provide exact commands to the primary owner. | Passing evidence with test counts and covered source; no duplicate check owners. |
| Browser journey | Give Terra the exact final local revision, disposable target, fixture and assertions. | Evaluate Terra's rendered/interaction evidence and own any necessary UI correction. | One isolated, muted real journey; affected checks repeated only if a correction changed covered inputs. |

The numbered waves below describe completion obligations, not a requirement to
serialize all backend work behind UI completion. In particular, wave 4 SQL can
be implemented alongside Astra's wave 3 UI after the contract is frozen. Do not
split backend invariants across extra workers or add coordination layers just
for parallelism. Required owners are the primary, Astra for UI/UX and Terra for
browser operation; production deployment is not part of this implementation run.

**Make the original case the first functional slice.** Use one reusable disposable
fixture: bounded form, nine admitted tickets, one waiting ticket, saved compatible
plan. First prove enable + usable organizer-managed assignment without queue
mutation. Add cross-form atomic units, eligibility/recovery and optional
publication to that SAME module/fixture family. This ordering is an integration
checkpoint, not permission to stop before the rest of the plan is implemented.
Do not create independent mock workflows that later need replacing.

**Minimize repeated setup and validation.** Reuse an already running, identity-
checked disposable DB and installed dependencies. Do not rebootstrap another
session's DB, reset shared fixtures outside the rollback owner, reinstall packages
or start a new server when the existing supported setup works. One initial
failing regression is useful; running checks after every edit is not. Batch
coherent source changes, then run the smallest affected SQL/Flutter/contract
selection. Run each final check once for its final inputs and retain its passing
evidence. UI-only changes do not invalidate unchanged SQL tests; SQL-only changes
do not invalidate unrelated vendor/package builds. Add a new selection or rerun
only when changed inputs, failure or an unresolved risk justify it. Clean-upgrade
validation, two-connection races and the real browser journey remain required.

Use the single workstation Flutter slot with `--concurrency=1`; one owner at a
time runs tests/analysis/builds. Never kill another session's task. Generate the
final migration once from final canonical SQL; validate its source/digest and
clean upgrade rather than repeatedly rebuilding the whole DB during development.
Do not run a production Flutter build, dispatch CI/deploy, rebuild vendor archives
or run a full unrelated suite as a substitute for these targeted checks.

Keep one compact completion/evidence checklist (wave, final input revision,
command, selected test count, result, remaining blocker) in the implementation
handoff or plan status. Log actual failures/timings only when they inform the
next action; do not build a tracking framework or claim estimated token savings.
Progress updates report a result, decision or concrete blocker, not repeated
polling. Each worker returns one concise handoff; one owner monitors each check.


### Wave 1: Domain projection, lifecycle and authorization

Create `database/functions/blueprint/seating_transition_schema.sql`,
`seating_transition_context.sql`, `seating_transition_lifecycle.sql` and
`database/functions/user_permissions/seating_transition_operations.sql` as the
canonical owners. Add the table/index/ACL, derived classification, scoped
capabilities and start/resume/cancel semantics. Extend explicit occasion/form
save/deletion/copy paths in sections 2-3. Preserve existing published forms.
Add explicit target selection to `get_blueprint_for_edit` and its Dart adapter
without removing the bounded occasion-only reader needed by installed clients.

Delete the prototype `blueprint_keep_form_capacity` input from SQL allowlists,
`OccasionCommands.save`, `DbOccasions.updateOccasion` and tests; delete
`blueprint_activation_choice.dart`, its test and its three translation keys.
Replace the prototype README paragraphs with the final domain contract. Keep
schema-2 empty creation and friendly error handling. Do not touch unrelated dirty
vendor/Flutter/web-client work visible in this shared workspace.

Gate: real SQL fixtures can enable editing even with no selected/repaired target;
they create no invalid target rows. Configured organizer-managed seating can
start/resume with occupied bounded AND unlimited forms, waiting/offers, and multiple forms without changing public admission mode,
identity or money. Ambiguous target/legacy plans produce a repairable context,
not a destructive reset. Unauthorized context and row writes are denied.

### Wave 2: Exact placement transaction and allocation preservation

Add `seating_assignment.sql` containing preview/commit and its private verified-
scope, eligibility and placement helpers. Extend the shared assignment lock owner
with explicit unassigned source orders/items and unioned before/after inventory
closure. Keep its existing private arity adapters calling the one implementation.
Update `inventory/apply_allocations.sql` addressed-seat eligibility and cleanup.
Use the existing mutation receipts, quotas and private inventory/sync completion
owners; update operation inventory/capability registration if required by those
actual owners. No monetary or product materialization helper in pure backfill.

Gate: an admission whose purchased price differs from today's catalog gains,
moves or releases its seat with identical financial snapshots, ticket symbol
and IDs. A sold-out product does not falsely require a second purchase. PIC
allocation totals stay correct after order reconciliation, provider callbacks,
product edits and normal cancellation. Conflict/replay tests pass at the public
entrypoint, not through a mock that has already assumed valid effects.

### Required UI/UX implementation owner

The user explicitly requires a `gpt-6-astra` subagent with `medium` reasoning for
UI/UX implementation. Spawn it with `fork_turns="none"` and a concise handoff
containing this authoritative plan, exact final SQL/transport contracts, scoped
files, design constraints and acceptance scenarios. Do not substitute the parent
model or another model for this work without a user override.

The primary agent owns domain/SQL decisions, contract integration and the final
coherent result. Astra owns organizer-facing interaction design and Flutter UI
implementation, including context/worklist states, exact mapping review,
publication, accessibility and recovery. It must identify contract deficiencies
before inventing UI-only policy; coordinate any required backend change with the
primary owner. Give the subagent exclusive UI files and a stable contract revision
rather than concurrent edits to its scope. Its handoff must include implemented
files, actual validation and any remaining UX risk.

Browser operation and navigation remain delegated to the repository-required
`gpt-6.1-terra` subagent in an isolated muted session. Astra designs/implements
and evaluates the resulting evidence; Terra operates the browser. This is not a
model substitution for the requested Astra UI/UX implementation.

### Wave 3: Real organizer worklist and shared read projections

Add typed Dart models and a transport adapter under `lib/components/blueprint/`,
then integrate the summary/worklist/review into `BlueprintLayoutHost` and the
occasion settings result notice. Use the existing state/draft/permission owners.
Update `DbForms.getBlueprintForEdit` for explicit target IDs. Apply canonical
seating read enrichment to affected admin/customer/ticket data owners; locate
remaining raw `orders.data.tickets` consumers with scoped searches in
`lib/components/eshop`, `web_client/src`, and `supabase/functions/send-tickets`
and change only those that present placement. Do not reserialize money.

Gate: organizer assigns from the rendered real worklist, reloads and sees the
same seat on the same admission. Nine admitted people plus one waiting person
can reach All assigned in organizer-managed mode without publishing, cancelling
or draining the queue. An order-only operator can complete configured seating;
a configuration-only editor can complete their part without holder access. Read-only/config-only roles see their appropriate
aggregate/private views; neither receives unauthorized mutation controls or
customer metadata. Review cancellation and reconnect recovery preserve drafts.

### Wave 4: Atomic publication and no-bypass admission rule

Add `seating_publication.sql` with preview/commit. Enforce cohort and dependent
source coverage, readiness/fingerprint and the exact configuration transaction.
Update the generic form-save guard, occasion feature disabling and applicable
`materialize_ticket_products_internal_v1` paths so neither old clients nor editor
creation bypass an addressed-seat requirement. Keep standing quantity behavior.
Align affected entrypoint lock ordering before extending inner guards.

Gate: the screenshot failure is replaced by preparation and completion guidance;
an organizer can use completed organizer-managed seating or separately choose
public seat selection when eligible.
Two-connection tests show publication versus checkout/offer/payment/geometry
mutations has one valid serial outcome. Empty, sold-out and shared-cohort
transitions are handled, while unresolved queues and protected/ambiguous data
produce explicit blockers rather than lost rights.

### Wave 5: Migration, absence proof and isolated journey

Generate the final migration from all canonical changed/new SQL in dependency
order. Replace the uncommitted prototype migration only after verifying it has
not been applied; if any ledger proves it applied, keep it immutable and create
a forward migration. Add new RPCs/capabilities/writers to the repository's actual
contract inventories where applicable, notably
`automation/client-sync/canonical-mutation-inventory.json` for tracked writers.
Update Blueprint/Forms READMEs and the implementation status in this plan.

Gate: clean disposable upgrade plus targeted tests below pass on final artifacts;
SQL source/migration digests agree; obsolete choice flag/dialog tests/translations
and automatic occupied-form activation are absent. An isolated browser journey
uses real disposable SQL for preparation, assignment and publication. Browser
interaction uses the required Terra delegation; no user's tabs or audio disturbed.
No production migration/deployment is implied by these local gates.

## 11. Validation matrix

Tests should cross the same public context/command interfaces as callers. Use
new focused files under existing `database/tests/blueprint`, plus representative
existing capacity, form checkout, allocation and ticket-print tests. New names:
`seating_transition_test.sql`, `seating_assignment_test.sql`,
`seating_publication_test.sql`; a bounded two-connection runner alongside existing
`database/tests/security/inventory_concurrency.test.mjs`. Do not make a broad
suite run a substitute for the specific races below.

| Scenario | Required observation |
|---|---|
| Screenshot-shaped fixture: cap 10, nine ordinary admissions, one waiting, optionally one held-for-waiting place | Enable succeeds, regular mode and all rights remain; nine admitted items can reach All assigned in a usable organizer-managed mode; waiting remains informational and is not auto-assigned; only optional public-selection readiness reports the queue blocker. |
| Unpaid ordinary ticket, add-on products, missing names | One admission row; accessories ignored; no missed reservation or fabricated identity. |
| Paid/Stripe order; catalog price/title changed since purchase | Pure assignment changes no money/payment/QR/state/product snapshot and sends no email. |
| Multiple holders in one order; partial offer acceptance | Stable ticket/item mapping, current order ownership and correct worklist after split. |
| Standing, dual-mode product, multiple-primary-item legacy data | Valid standing allocation covered; ambiguity is visible and cannot mutate/publish. |
| Used/batch-printed/stock/cancelled/preparing-payment cases | Exact policy in section 4 at context AND mutation; no guard bypass or unsupported action. |
| Same product at maximum; seat with/without PIC context; shared quantity >1 | No extra purchase; before/after canonical allocation totals and other entitlements preserved. |
| Ordinary order reconciliation after manual assignment | Explicit placement remains; no free addressed seat auto-claimed by generic allocator. |
| Couch assign/move/release; one admission for two-seat unit | Complete atomic mapping only; no cloned ticket or partial change. |
| Stale layout, seat reprice/reproduct, live/expired hold | Relevant conflict and no partial mapping; expiry evaluated after waits. |
| Two organizers choose same seat for different tickets | Exactly one succeeds; loser has typed conflict; no duplicate placement. |
| Assign versus cancellation or scan/use or immutable print creation | One serial result respecting current ticket/artifact state. |
| Publish versus new checkout/accepted offer/provider completion | New obligations included before publication or writer observes new mode afterward; no orphan seatless admission. |
| Two forms share a target; one couch needs admissions from both | One explicit cross-form mapping can assign/move/release the complete couch after per-item authorization; no partial-unit exception. |
| Two forms share a target; new source form appears after preview | All cohort publication is atomic; changed publication membership/source requires review. Unrelated work does not discard valid assignment drafts. |
| Config-only, order-reader and order-reader/writer users | Each can load the allowed usable context independently; publication is config-gated, holder rows are order-read-gated and assignment uses order-write plus exact authorized context. |
| Enable with ambiguous/legacy-invalid target | Feature enables and public mode stays unchanged; Choose/Repair UI appears with no dummy transition row. |
| Direct ordinary/ad hoc editor call after publication with admission product but no seat | Rejected by domain rule, including stale visible-primary-field payload. |
| New/copied/reopened regular form or newly added addressed SKU after publication | It cannot restore an unseated emitter behind the published plan; valid shared-plan seat selection remains possible. |
| Retained inactive blueprint on feature enable; cancel preparation afterward | No transient active seat sales, no lost saved plan/assignment, no implicit reactivation of the old binding. |
| Timeout after commit, duplicate click, reconnect replay, same UUID with different payload | Original receipt recovered once; changed payload rejected; no duplicate audit/mutation/email. |
| Revoked writer while waiting; foreign scope; private-row RLS | No mutation or unauthorized receipt/context data, including after lock waits. |
| Cancel/restart; disable feature; copied/deleted forms/plans | No implicit unassignment, no stale identity reuse and no copied operational transition. |
| Existing order/PDF/email/admin views | Same authoritative seating and original finance; old QR remains valid; no mutation to historical snapshot/immutable batch PDF. |
| Browser journey with pagination/filter and unsaved geometry | Full server coverage regardless of visible page; draft guard, keyboard dismissal, retry and capabilities work. |

Run at most the targeted affected checks, using repository commands:
`DATABASE_URL=... pnpm --dir web_client exec node scripts/run_db_tests.js <exact-files>`
on a marked disposable database; `fvm flutter test --concurrency=1 <exact-files>`
after checking the workstation slot; targeted `fvm dart analyze <changed-files>`.
Verify test discovery counts. Select existing regression files via `rg --files`
under the owning test directory; do not guess paths or silently run zero tests.
No tests/builds are needed merely to edit this plan.

## 12. Removal, deployment and rollback

| Current artifact/behavior | Final treatment |
|---|---|
| `blueprint_keep_form_capacity`, confirmation helper/dialog and three translation keys | Delete from prototype SQL, Dart, docs and tests; no alternate flag retained. |
| Fictitious `blueprint:1` occasion-wide validation | Replace with lifecycle/actual-active-form validation. |
| Automatically attach an occupied unlimited or bounded form on feature enable | Remove; use explicit preparation/publication. |
| Implicit first-plan selection during multi-plan transition | Replace with scoped target selection; retain only unambiguous installed-reader adapter. |
| Existing financial replacement/swap | Retain for explicitly financial changes; never delegate pure backfill to them. |
| Existing waitlist guards | Retain and route through publication readiness; no automatic queue cancellation. |
| Prototype migration | Do not deploy; verify ledger before replacement, otherwise forward-only correction. |
| Historical commercial snapshots, terminal transition rows, command receipts | Preserve as history, not a competing placement authority. |
| New participant route/token infrastructure | None in this release; the verified-scope seam is sufficient. |

Local implementation follows these waves. Production release requires canonical
source/tenant and backend-activation verification and the existing production
release procedure; it remains unperformed. Stage schema/commands/guards before
the matching UI. During the compatibility window old clients cannot bypass
readiness and receive stable actionable failures; do not use triggers or accept
a generic form-save flag to bypass publication. Deploy only the selected tenant
when authorized; a shared backend function change still needs impact verification.

Before applying SQL capture function definitions/digests, migration-ledger state
and rollback evidence through the approved backend-access workflow. Apply SQL
and ledger atomically, notify PostgREST as required, verify exact definitions,
ACLs and a read-only receipt/context probe. Never run synthetic tests on production.

If UI rollout fails after schema expansion, keep preparations and placements
intact and retain the guarded old sales mode; disable only the new UI entrypoint
as needed. Do not automatically undo assignments or re-enable generic unlimited
admission. Once published seat sales exist, rollback of UI/code is not rollback
of business transactions. Operational reversal must preserve those sales.

## 13. Known limits, completion and planning evidence

The first release does not retrofit onto an already-public target, reseat used
or batch-printed admissions, resolve ambiguous historical primary items, assign
a mixed seat/standing SKU, or migrate a live waitlist to seat promises. These
are explicit early-visible blockers, not implementation-time guesses. The
organizer can still enable/edit/prepare and preserve ordinary sales. Broader
support must extend the same domain module with an independently specified
policy and tests, not bypass safeguards. Unsupported data must never be silently
excluded from final coverage to make publication pass.

Completion requires usable organizer-managed seating as a complete supported
outcome, the separately optional publication flow, preserved commercial identity,
exact lifecycle/permission/concurrency tests, all entrypoint guards, canonical
read projections and removal of the superseded prototype. A notice or this
architectural document alone is not implementation completion. Future participant
access must need an authorized scoped adapter and UI, not a copied assignment
algorithm or a second reservation store.

The initial hardening used a focused source audit of the evidence above and one
adversarial completeness pass over allocation, financial snapshots, publication
cohorts, bypass writers, role revocation, retries and rollback. No application
code, production data, migrations or external state was changed by this planning
turn; previously existing uncommitted implementation work remains untouched.


The user-requested `gpt-6-astra` / `medium` architecture and UI/UX review on
2026-11-01 then corrected the substantive product/contract gaps IN the sections
above: organizer-managed seating is a complete mode; optional publication is
separate; unresolved targets create no dummy configuration; assignment scope
supports cross-form atomic units; capabilities allow order-only operations;
compatibility checks precede pairing; queue/canvas/recovery states are explicit;
leaving the workspace does not undo placements; terminal provenance does not
indefinitely prohibit otherwise legal parent deletion. This was a read-only
subagent review with targeted source inspection, not application validation.

Astra's integration check confirmed the revised journey/contracts and required
implementation ownership. Its final clarification is incorporated in section 3:
`UNCOVERED_ADMISSION_SOURCE` gates optional publication, never otherwise valid
manual assignment. The review and integration check ran with `gpt-6-astra` at
`medium`; neither ran app tests or changed implementation files.


Implementation completed in the explicitly started execution on 2026-11-01.
See [local implementation and validation evidence](blueprint-admission-transition-RESULT-2026-11-01.md)
and the [actual transport contract](blueprint-admission-transition-CONTRACT-2026-11-01.md).
All five waves have local implementation and targeted evidence; production
migration/deployment remains separately authorized and unperformed. The retained
prototype migration is superseded forward-only, with the operational atomic-release
requirement recorded in the result. No participant access infrastructure was added.
