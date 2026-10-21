# Blueprint (visual seat selection)

The public `venue_seat_picker` package owns V2 geometry, rendering, gestures,
selection activation and history. Festapp owns products/prices, explicit commercial
group membership, seat-to-spot bindings, permissions, orders and command receipts.
The generic package never receives a Supabase client or private order metadata.

Runtime readers and writers require the canonical schema-2 document. A load/save
failure remains repairable and never selects an old renderer. The explicit
reviewed legacy importer is an offline conversion boundary, not a runtime route
or a reader side effect. SVG authoring originals remain private; renderers use
prepared portable paths.

## Geometry and business state

Geometry and commercial binding changes form one revisioned draft. Selection alone
does not dirty it. Group defaults are explicit; mixed or unassigned groups do not
invent a price. New seats inherit a known group default, while protected ordered,
used or actively held seats cannot be structurally rewritten. Existing `spot.id`
stays stable when geometry changes. Commercial protection follows actual holds,
orders and used tickets; it is distinct from the authoring `node.locked` flag. Copy creates fresh identities without holds
or order/ticket assignments.

`FormCommands.saveBlueprint` uses `update_blueprint_client_sync_v1`, the existing
receipt and sync boundary. SQL validates the entire geometry/binding aggregate
before commit. An ambiguous retry retains the same command UUID and frozen input;
a late response must not erase newer draft edits. `_v1` names this public protocol,
not the geometry version. Catalog edits and confirmed order commands take effect
immediately and are not reversed by geometry undo or draft discard.

## Reservation and financial authority

Both customer pickers apply optimistic presentation through the package and
rollback rejected callbacks. Only `select_spot` creates/releases the actual
secret/expiry hold. SQL locks the complete atomic unit, validates the assigned blueprint bindings,
visibility, maximum and shared PIC capacity, then changes all members or none.
An owned retry keeps its original expiry; release remains possible after an
offer closes. Existing active addressed holds count through PIC quantities even
when the held spot has no direct inventory context. They use the existing spot
hold records, not a second reservation ledger.

Public checkout checks the form's own blueprint, unique seat IDs and a non-null
matching, unexpired hold after acquiring its locks. Form schedule and hold expiry
use the current database clock after lock waits. Successful assignment consumes
the hold. Only a verified order editor can replace seats without a customer hold;
another buyer's active hold remains protected. Replacement uses the selected
blueprint's form and its required ticket answers; payload fields cannot replace
the server's chosen form or seat list.

Refresh replaces the selection with the public server projection and restores the
original own-hold `expiresAt`. Public blueprint `data` is an empty allowlisted
object. Bindings expose sale state and commercial identities, with one catalog
row per product; order/customer metadata, secrets and private asset originals stay
outside that projection.

Assigning a blueprint to a form offers its bound seats and capacity areas. No
duplicate product-type form field is required. Questions and optional product
fields remain separate. Standing quantity uses the blueprint catalog and the
existing inventory/finalization owner. Changing quantity does not create a seat hold.
Checkout uses `send-ticket-order` and `create_ticket_order_client_sync_v1`;
admin replacement uses `replace_blueprint_order_client_sync_v1` and the existing
conflict/cancellation owner. Swaps use the existing preview, receipted command,
financial recalculation and history. Clients never calculate authoritative money
or publish a success before the command receipt. Refresh restores server state.

## Fonts, images and setup

The editor paints authored text with the actual registered native font face and
transient Flutter paragraphs. Geometry changes do not dispatch whole-text shaping.
Explicit save and entry into reservation viewing prepare the captured document's
canonical whole-text vectors through the shared HarfBuzz owner. Saved/native
viewing and public SVG viewing consume those vectors; there is no public native
font fallback and no second persisted scene/document. Numeric symbols and
imported SVG paths retain their canonical prepared representation.

Both editors use `venue_seat_picker/editor_ui.dart` for font-style/alignment
controls, color picking and numeric wheel stepping. Hosts retain their own value
validation, QR contrast policy and save/undo commands. `EditorDialogDismissal`
owns route-scoped Escape handling, including lost focus and nested menus; the
application dialog shell delegates to it.

Public readers receive only referenced validated resources. The Image Worker
processes bitmap backgrounds and registers exact byte hash, dimensions, MIME and
length through its scoped capability. Canonical save checks owner scope and
readiness; consumers verify bytes before decoding. SVG originals, private image
records and proof keys never enter public projections.

Setup drafts persist typed geometry and commercial bindings without source spot
IDs or binary resources. Unit-scoped resources work before the occasion exists.
Final creation remaps identities through existing product/inventory and aggregate
save owners. Shared configuration-copy helpers preserve exact resources and named
slots, with no reservations. The separately marked offline demo uses package
fixtures only and calls no business commands.

Named appearance styles use existing canonical `presets` records with empty-node
preset documents and declarations in `styles.kinds`. They are saved with the
plan, offered in the object style strip, and managed through the style overflow
menu (create, rename, delete; all changes support undo). Applying one copies
presentation only and preserves object geometry, names and seat identities.
Font-size dragging uses the shared gesture-based slider. Bold and italic are
available only when the selected immutable family manifest includes the actual
requested face; the UI explains unavailable cuts. Unsupported underline is not
shown in Blueprint, while the shared Ticket control retains it.

New seat-product suggestions prefer the last explicit assignment, then the most
used eligible priced seat product, with catalog creation time/ID as a tie-break.
Only new bindings/groups receive a suggestion; existing assignments stay in their
draft checkpoints. Explicit product selection on a whole-table card replaces
free-seat exceptions and returns them to inheritance in one undo step. Protected
booked/held seats retain existing guards. Product assignment is persisted only by
the plan Save owner; catalog create/name/price editing remains its separate
catalog operation and keeps its notice inside the actual catalog edit dialog.
Plan style opens as an inspector page with reversible family/palette hover
previews; clicking commits one history entry. Floor and detailed controls are
collapsed. Closing/Escape cancels a pending preview without blocking the canvas.
The shared font picker offers promotion to `styles.label` only after an explicit
font change in that scope and only while it differs from the document default;
it uses the existing preparation owner. Object-specific overrides remain explicit.
Seat addition is disabled at the table geometry or document seat limit.

Rejected furniture translations render transient red target hulls outside the
document/history while retaining the last valid placement. Copies expose existing
placement warnings only on the copied subtree; moving clears those warnings.

Reservation workspace uses the public `libraryOverride` seam for the table list
and `inspectorOverride` for persistent grouped selection details. Selecting a
seat highlights its owning table on the left; commercial selection does not
change geometry. Product/price assignments remain plan drafts until Save.
Cancellation resolves selected seats/tables to distinct active ticket IDs,
confirms the ticket selection, rechecks rights/session/associations, and calls
the existing ticket command. Live availability refresh preserves the plan draft.
Partial and full cancellation emails share the TicketsTab follow-up helper and
are optional after the receipted cancellation. The final ticket still cancels its
order automatically. Other bulk SQL callers retain their explicit notification
policy. Temporary holds have a separate order-editor-only release command, with
scope validation, atomic seat-unit expansion, row locks and replay receipts;
ordered spots are rejected and no ticket or payment is changed.

Pointer copy/move rollback is owned by pointer cancellation and Escape; incidental
keyboard focus transfer does not discard an active clone. Numeric property and
slider fields share focused wheel edits with normal validation/commit behavior.
Graphic import is one image/SVG action with the existing combined allowlist.

Operation entry reuses commercial selection: order mode expands atomic units and
seeds only available priced seats; swap mode seeds at most two eligible seats,
leaving larger selections unseeded. Existing confirmation/command owners remain.
Reservation mode needs no separate select/pan toolbar controls.

Blueprint font selection opts into shared hover/keyboard previews in a transparent
side dialog. Temporary font metadata edits use one controller gesture and are
canceled on exit/Escape/dismiss/session replacement; choosing uses the existing
permanent font owner. Ticket picker defaults remain unchanged. Manual attached
chairs can restore automatic placement through the canonical seating command,
from inspector or context menu, with normal protection and history semantics.

Graphic resizing preserves aspect ratio by default; Shift permits free resizing.
Committed inspector number fields route undo/redo to document history and retain
focus after Enter; uncommitted text keeps native field history. The cinema family
uses existing canonical material values. Galaxy cinema is a portable dark template
with seven rows, 84 seats and four atomic two-seat couches; bundled text resources
cover both English and Czech template labels.

Selecting an attached chair shows its own boundary-to-boundary table connector;
selecting the table still shows all attached chairs. The Text section offers a
counted transfer to editable peers of the same kind. Only resolved label styling
is replaced, including existing peer overrides; locked objects are skipped.
The transfer is one document history entry and leaves document defaults intact.

Layer and commercial-list hover use transient controller highlighting. Hover
expands geometry subtrees/commercial membership without changing selection or
history. Reservation toolbar blocking expands atomic seat units, skips protected
units and changes all eligible bindings in one undoable draft transaction.
Secondary toolbar actions use icon buttons with tooltips on narrower screens.
Only explicit plan save shows the host's progress bar; order analysis is prepared
before opening the dialog, and pending submission keeps a stable disabled button.
Order analysis returns required customer and attendee fields from the same open
form selected by the server. The dialog reuses shared form controls/validation;
answers use the canonical customer and per-ticket field payloads. Confirmation
pins the analyzed form and rejects a different current form. Client data cannot
override the selected form or server-generated ticket list.

Standing sales capacity uses the existing areaBindingChanges.capacity intent,
separate from geometry. Effective initial capacities come from live availability;
full capacity values participate in private history checkpoints, including zero.
Save freezes capacity metadata alongside the document before text preparation.
Undo after save therefore restores an explicit inventory capacity change, while
geometry-only saves omit capacity. The reservation detail shows available places
and a focused numeric control; product/physical inventory limits still apply.
An unbound standing area can assign a visible, priced admission (`spot`) product.
The setup reuses its existing quantity-one inventory context (unique within the
blueprint), or prepares a pool, context, resource supply and product-context link
through the inventory/catalog commands. Existing sold products without inventory
are excluded from this shortcut. Product and inventory preparation is immediate;
the initial binding and sale-limit intent are undoable until the plan is saved.
The sale limit is a ceiling, not additional physical supply: increase resource
capacity in Inventory when more supply is needed. Shared pool limits affect all
its products and contexts. Form offers and checkout continue to derive admission
from saved bindings through the existing blueprint form-product projection.

Preparation retains successful pool/resource steps while the dialog retries,
including switching products. Closing after a partial failure leaves these
entities saved and manageable in Products/Inventory; it does not attempt unsafe
compensating deletion. Reopening starts from the authoritative catalog. A new
preparation can therefore leave an unused pool from an earlier incomplete setup.

The editor workspace adapts to theme brightness while authored document fills
remain unchanged. Neutral line thumbnails use brighter strokes in dark mode and
a minimum visible stroke width; material thumbnails show their canonical family.
The default unstyled seat uses the shared saturated green in scene and previews.

Viewing shortcuts use the same authorized host mode transition: triple-click the
canvas, or double-click an already selected object. Selection transfers to the
geometry inspector. Shortcuts are absent during order/swap operations and for
users without plan editing rights; they never create history entries.

The footer info action opens concrete controls for the current mode, with seat
states collapsed below. New non-text drops return focus to the canvas; clean
inline text sends undo to the document transaction while typed drafts retain
native undo. All package editor modal entry points use the shared route-scoped
Escape dismissal. Row groups can split into independent seats with identities
and world transforms preserved; Alt-click or the seat context action selects
a child without splitting. Default seat green matches V1 (#267329).

Order/swap selection uses a host-owned floating summary anchored inside the
canvas; order amounts sum selected seat products separately per currency. Final
order analysis/confirmation remains server-owned. The top toolbar contains no
operation summary and delegates dirty indication to its existing Save control.
New generated row seats use row-number plus alphabetic column (1A...1Z, 1AA),
continuing across blocks. Host commercial reconciliation keeps those titles;
assembly resizing updates only automatic labels and preserves custom names.

Native font preview failures are scoped to active rendered faces. Cache identity
includes actual face metadata; late failures of abandoned choices do not affect
the current face, and active load failures offer retry. Text-tool thumbnails use
a schematic theme-colored Aa without requiring prepared authored text resources.

Changing a font family normalizes only affected declarations/nodes to an actual
available 400/700 normal/italic face in the same undoable edit. Supported styles
and independent font choices survive. Renderer fallback/synthetic faces remain
disallowed; existing B/I controls disable unavailable face combinations.

Reviewed legacy conversion preserves semantic table labels separately from
appearance normalization. Existing SVG text nodes remain unchanged. An explicit
`tableLabelStyle` review profile can promote typography to the canonical table
kind while clearing conflicting local leaves; it never invents unsupported font
faces. Unprofiled plans preserve their original typography. Table labels use the
centered, shrink-to-fit label box by default.
