# Forms (Dynamic Data Collection & Ticket Ordering)

## The Form Bundle (CRITICAL)

Forms are NOT simple definitions. `get_form_by_link` RPC returns a massive bundle:
- Form metadata + field definitions
- Products with dynamic availability (checked via `is_product_dynamically_available` SQL)
- Session `secret` UUID for spot locking

If a product isn't showing, check `is_product_dynamically_available` in SQL, not Dart.

## Gotchas

- **Never hardcode field IDs**. Find fields by `type` or `data` attributes -- IDs are generated.
- **Two submit paths**: Registration -> `create_form_ws` RPC. Ticket orders -> `send-ticket-order` Edge Function.
- **`widgets_view/`** = runtime (user-facing). **`widgets_editor/`** = design-time (admin drag-and-drop). Don't mix them.

## Rendering Engine

`FormPage` calls `DbForms.getFormFromLink`, iterates `form.fields`, selects widget by `field.type`, collects data into `FormHolder`.

## Email suffix confirmation

Public email fields in both clients use the same offline
[IANA snapshot and update procedure](../../../shared/email/README.md).
After syntax/required checks pass, an unknown suffix requires explicit confirmation
of that field's current value before the ordinary submit action. Confirmation
never submits, is revoked by edits, and remains only in the current form session.
Visible ticket email fields follow the same rule. Login, reset and Google proof
remain outside this confirmation gate; manual web registration uses it.

## Before registration opens

The countdown message can contain an atomic `div.html-editor-block.form-countdown`
slot. The editor shows a live timer with up/down controls between editable text
blocks; both public clients render the timer in that saved position. Titles
without a slot retain their historical text-then-timer layout. The slot carries
no date: the schedule remains the only source of the opening time.


The schedule's optional `show_before_start_message` and `before_start_message`
add rich information below an enabled countdown. Existing forms keep countdown-only
behavior. The message uses the normal HTML editor and media-save coordinator, so
organizers can publish text, images and a hall-plan image without enabling seat
selection or registration. Hiding the message retains its draft. Manual closure
still wins, and countdown completion reloads the current server bundle.

## SQL RPCs

- `get_form_by_link` -- complete form bundle for user rendering (includes session secret)
- `get_form_for_edit` -- form + fields + products + bank accounts for admin
- `create_form_ws` -- creates an administrative form; participant registration uses the order endpoint
- `update_form` -- updates form metadata
- `duplicate_form_to_occasion` -- copies form to target occasion
- `get_blueprint` -- loads blueprint seat map for form session

## Editor deletion

`get_form_for_edit` returns `can_delete` and `delete_blocked_reason` for each
field/product. Missing usage metadata keeps saved items non-deletable. The
editor stages explicit `deleted_field_ids` / `deleted_product_ids`; only the
existing form-save command applies them in `update_form_internal_v1`. Partial
settings saves never infer deletion from omitted fields.

Save checks current answers and current order products (including cancelled
orders), blueprint spots, inventory links, and shared product groups. Removing
a ticket container includes its nested fields; removing a product field also
removes its unused products. The form row lock coordinates save with order
creation and response editing; product/type locks protect concurrent FK links.
Historical snapshots alone do not block deletion; order history remains intact.
A rejected save rolls back every change and leaves the editor draft intact.

## Editor draft actions

The form, settings, and design tabs use `EditorActionBar`: Save and Discard
changes are disabled until editable values differ from the loaded baseline.
Discard confirms, reloads the tab, and never pops the administration route or
invokes its close callback. Model snapshots include nested fields, products,
and staged deletions. Child editors report changes to refresh the action bar;
plain text fields also use the surrounding Form's change callback. HTML drafts
that are still open are included via `HtmlSaveCoordinator.hasActiveDraft`.
Keep model getters free of writes so rendering defaults does not create edits.

## Single-application form

When both the ticket and blueprint features are disabled, the editor hides the
order-quantity setting and saves `max_tickets: 1`. Read-only inspection hides it
too. Ticket-enabled or blueprint-enabled occasions retain the quantity editor.
Feature checks use the form's owning occasion, including isolated setup drafts.
Email authoring examples use a single application and its price in this mode;
blueprint-enabled applications and ticket orders retain the multi-item sample.
The build-time generator owns the canonical single-item email markup.

## Global ticket order limit

`MAX_TICKETS_PER_ORDER=20` in `automation/project.conf` is the technical ceiling
for every order, including editor-created orders. Individual forms may choose
lower limits. `apply_config.sh` generates the Flutter/public-client cap; values
above it cannot be typed into the form editor and old oversized settings are
clamped when read. SQL rejects oversized form settings and order payloads before
creating any tickets. To change the ceiling, run `apply_config.sh` and
`python3 automation/assemble-ticket-limits-migration.py --output supabase/migrations/<timestamp>_global_ticket_order_limit.sql`; ship the resulting SQL
and both clients together. After the initial migration is deployed, publish a new
migration for later cap changes instead of rewriting the deployed migration.

## Participant capacity and waitlisted orders

Capacity counts DISTINCT eligible `eshop.tickets` through existing
order_product_ticket links, including unpaid regular orders. Waiting tickets and
storno do not consume occupied capacity. There is no person ledger or backfill. `participant_capacity=NULL` preserves unlimited registration. Forms with an enabled blueprint feature and an attached blueprint cannot enable
this limit or waitlisting. A stored blueprint is retained but ignored when the
occasion blueprint feature is disabled. Form saves preserve omitted
settings; removing a limit uses an explicit NULL. Live waiting tickets or offers
block disabling waitlisting, removing the limit and switching to a blueprint.

The server bundle owns `capacity` and `registrationMode`. Public availability
subtracts eligible tickets, valid offer slots and the priority of active waiting
tickets. Expired offers cease holding capacity even before the bounded cleanup
job runs. Clients must use the snapshot rather than calculate availability.

Waitlisted orders collect contact answers and waiting tickets with their own
answers, without sale products or payments. Waiting tickets are not valid
admissions and have no ticket symbol. Acceptance reuses their ticket IDs. Editors explicitly confirm offers of a number of places. A personal
link opens a prefilled form; only its explicit submit accepts selected tickets
and currently available products. Offers hold person capacity only. The same
per-order person ceiling applies to both modes. See the
[implementation contract](../../../docs/plans/form-capacity-waitlist-plan-2026-10-13.md).

## Payment and reminder defaults

Each form inherits the occasion's Form feature unless an explicit override is
stored. `forms.deadline_duration_seconds = NULL` inherits the feature deadline
(default 7 days); zero is an immediate deadline. This resolves when creating a
payment or recalculating its deadline, without rewriting existing deadlines on
settings saves. In `forms.data`, absent/null `is_reminder_enabled` inherits the
feature (default true), while explicit false/true overrides it. Absent/null
`reminder_interval_seconds` inherits the feature (default 1 day). Clearing a
form override restores inheritance, so subsequent occasion changes apply.
The Form feature itself must remain enabled for reminders to send.

Both reminder queueing and send-time eligibility honor the same enablement
precedence, including deposit reminders. Queue timing uses persisted per-form
and per-occasion values; the legacy interval argument on
`queue_payment_reminders` remains callable but no longer overrides them.

## Customer order overview

Waitlist registrations, offers and resulting orders share one stable customer
URL: `/order?order_id=<root>&token=<view>`. Form-based and hash capability URLs are not accepted. The same root token is reused by every order
email, including split children. Query capabilities are protected by no-store,
no-referrer and noindex response headers; never log or persist them in clients.

The page reads `get_customer_order_overview` through POST RPC without offline
storage. While visible it refreshes every 30 seconds and immediately after
returning to the tab; unchanged content keeps its DOM and there is no refresh
button. Leaving the page cancels polling and ignores pending responses. SQL allowlists current payment facts, matched transaction dates/amounts,
and recorded history transitions and item/price changes. Private transaction
metadata, admin notes and raw history payloads are never returned. Timeline
entries are historical observations; the current payment status distinguishes
paid deposits from fully paid orders.

View access permits reads only. Accept/decline and waiting withdrawal retain
their existing write capabilities on `/order?waitlist=1`. The
orders grid opens the same view URL through authenticated
`get_order_overview_admin_context`, which checks order-view permission before
`customer-order-access` opens or initially creates the root's encrypted source.
It never rotates a token or sends a standalone email. Expired/revoked sources
are not replaced. `ORDER_OVERVIEW` is retired from the template catalog.

The journey migration is `20261015210000_customer_order_journey.sql`, assembled
from `order_overview.sql` and `order_overview_admin.sql`.

Use `python3 automation/assemble-order-overview-migration.py --check` for source
parity; do not regenerate the published capacity migration for this follow-up.
See [implementation and targeted evidence](../../../docs/plans/order-overview-waitlist-follow-up-implementation-2026-10-15.md).

## Public URL ownership

SQL `public_links/registry.sql` owns current and historical public slugs. New
items with a blank slug receive an independent cryptographic 8-character code.
Explicit changes use lowercase ASCII letters/digits and single hyphens, up to
80 characters; unchanged legacy links are retained exactly. Domain commands
reserve URLs atomically with writes and receipts. Reservations survive deletion
as tombstones. Aliases resolve to stable IDs under the existing permissions.

Settings keep a separate server-confirmed link baseline: Copy uses the saved
public URL, while an unsaved proposal is plain text. Loaded aliases replace the
URL without adding history or discarding query/capability fragments. Unknown
aliases require an online resolve. Occasion copy locale is captured once and
persisted in the command/draft; SQL alone owns the localized copy title.

Existing cross-tenant occasion duplicates keep frozen tenant-scoped ID bindings.
New writes cannot claim those slugs; canonical links and titles are never bulk renamed.

Veřejné vložení formuláře používá stejný checkout. URL, integrační varianty,
bezpečný protokol a limity obnovy vlastní
[embedded checkout contract](../../../docs/integrations/embedded-checkout.md).

## Selection validity

Choice fields must have at least one nonblank string option. Editor validation
retains the draft and marks the field; the form-save SQL validates the same
contract transactionally. Partial settings saves do not revalidate omitted
fields. Public readers tolerate legacy missing options so one malformed field
cannot turn the whole form into an unavailable page.
