# Occasion setup - deeper copy QA, 2026-10-21

Result: six additional defects confirmed. No product-code changes or production
writes were made in this session. This report supplements
[the initial QA](occasion-setup-qa-2026-10-21.md); it does not replace the repair
session's verification of the original defects.

## Scope and evidence quality

Tested the dirty working tree on `feat/occasion-setup-wizard-20261007`, HEAD
`eb2304724`, after the concurrent repair session applied migration
`20261021190000` to the owned local `festapp-wizard-qa-20261021` backend.
That session converted historical source fixtures 5-8 to current ticket layout
schema 3 using the existing converter. The ticket findings below use valid
schema 3, independently of the earlier obsolete-fixture problem.

Real browser: isolated headless session `wizard-deep-20261021`, explicit empty
config, local real app entry `test/browser/occasion_setup_e2e.dart`, API 56821,
Flutter server 56880. Production service requests blocked; the existing entry
fixture stubs push callbacks. Flutter semantic clicks were needed as in initial
QA. Pointer hitboxes, dragging, date pickers and external PDF generation are
not certified by these results.

Findings 1-3 were reproduced through actual UI interactions. Findings 4-6 use
authenticated calls through the real source/draft/finalize SQL boundaries with
inspection of committed-in-transaction rows, then ROLLBACK. Controls separate
invalid fixture data from actual failures. SQL sequences advance on rollback.

Private local artifacts and probe scripts:
`/tmp/festapp-wizard-deep-20261021/`. They are exploratory evidence, not committed
CI tests. No tests or product fixes from the other session were overwritten.

## 1. Selecting No blueprint still creates the inherited blueprint

Reproduction:

1. Create a copy of Skautsky ples 2026 from its event card.
2. Keep its form. At the blueprint question, change Inherit to No blueprint
   (`Bez plánku`).
3. Skip verification, approve review, create the event.

The UI accepts this configuration and hides the blueprint editor. Nevertheless,
the resulting event contains a blueprint with all 182 inherited seats. Browser
creation produced local occasion **54**, `Deep QA Bez plánku`; its draft stores
`blueprintMode=Bez plánku` and 182 `blueprintObjects`.

Cause: `occasion_setup_page.dart:_choice` retains objects when selecting No
blueprint. `database/functions/occasion_setup/finalize.sql` creates a blueprint
whenever objects are nonempty and does not consult `blueprintMode`.

Evidence: `no-blueprint-review.snapshot`, `matrix.jsonl`. The independent
rollback case `blueprint_disabled` also created one blueprint and 182 seats.

Fix direction: honor the explicit selection at the materialization boundary;
make the draft/UI contract consistent. Preserve intentional editing semantics
when toggling back, rather than deleting configuration indiscriminately.

## 2. Replacing the form leaves seats attached to removed products

Reproduction:

1. Create another copy of Skautsky ples 2026.
2. In the form question choose Create/Copy form, confirm replacement, then
   Create new empty form.
3. Keep the inherited blueprint and complete review.

Review reports **5 of 5 settings without errors**. Finalization fails with
`{"code":4004,"message":"Invalid seat product"}`. The generic Retry/Back
screen hides the actionable reason. No partial event is committed.

The new form contains its canonical Spot product; the inherited seats still
refer to the old form's product IDs. `_chooseForm` adopts a new blueprint only
when the replacement form has one; the new/default form has none, so the old
blueprint survives. `_reviewIssues` checks object/product counts but not whether
seat products belong to the currently selected form.

Persistent local reproduction draft:
`908d647b-0146-40e4-81b5-4630adc66ab7` (title remained the generated copy title).
Evidence: `replaced-form-review.snapshot`, `replaced-form-failure.png`; database
log at 12:32:36 UTC. Its form and blueprint were changed through the actual UI.

Fix direction: define what form replacement does to inherited seat/product
bindings and require reconciliation or a clear choice before confirming review.
Do not weaken blueprint ownership validation.

## 3. Equal source titles and dates crash source selection

Fixture: two distinct synthetic local occasions with identical title
`Deep QA shodný název` and start time 2026-12-01 18:00 CET, different IDs and
slugs. Both are valid source rows, hidden and closed, without customer data.
Their local IDs are **63 and 64**, marked with
`external_source=wizard-deep-20261021`.

Reproduction: start a new step-by-step wizard, open Source and select the second
of the two identically labelled entries.

Actual: red Flutter error screen, with no working wizard controls:
`There should be exactly one item with [DropdownButton]'s value`.

Cause: `_sourceLabel` combines title and date; `_choice` uses that text as the
dropdown value, and `_applySource` resolves it with `firstWhere`. Source identity
is therefore ambiguous even apart from the debug assertion. The wizard itself
is currently a debug-only feature, where this assertion is active.

Evidence: `duplicate-source-console.log`, `duplicate-source-crash.png`.
The resulting synthetic-source draft is
`4e3776d5-4a61-462f-8e94-d2d41022b15f` and selected source ID 64 despite clicking
the second entry. Reload returned to the event list.

Fix direction: use the source ID as the stable value; labels are presentation.
Keep distinct entries understandable when their human-readable labels coincide.

## 4. Form copy silently drops capacity and waitlist configuration

Rollback-only source fixture, based on local source 4:

| Setting | Source | Finalized copy |
| --- | --- | --- |
| `participant_capacity` | 10 | null (unlimited) |
| `waitlist_enabled` | true | false |
| `show_remaining_capacity` | false | true |
| `waitlist_offer_duration_seconds` | 3600 | null |

The probe updated the source form inside a transaction, called
`get_occasion_setup_sources`, saved its returned form into a fresh draft and
finalized it. It inspected the new form and rolled back **all** changes. Other
sessions could not see the temporary source settings.

Cause: `database/functions/occasion_setup/sources.sql` omits these configuration
columns. The draft adapter and form writer support them, but the copy manifest
loses them before the editor sees the form.

Evidence/reproduction: `node /tmp/festapp-wizard-deep-20261021/capacity.mjs`,
result `capacity.json`. The result records the original values, actual manifest
keys and resulting copy values. The probe succeeds in finalizing; this is silent
configuration loss, not a validation failure. New event/form remain closed.

Fix direction: preserve configuration through the manifest, while excluding
live capacity counters, participants, offers and other runtime state.

## 5. Existing custom ticket fails after replacing its product form

Rollback-only paired control:

1. Use an inherited, valid schema-3 layout based on the repository's
   `test/fixtures/ticket_layout/layouts.json`, with a productType element bound
   to an existing source product type. Remove blueprint objects to isolate the
   ticket behavior.
2. Finalize with the original form: **passes**, binding is remapped to a new type
   owned by the copied event (observed new type 106).
3. Repeat with the new form serialized by the actual UI in finding 2: **fails**
   with `Invalid product field`.
4. Repeat the same replacement without the inherited ticket: **passes**.

Cause: `_chooseForm` leaves `ticketDraft` referring to a removed product type.
Finalization's `type_map` has no corresponding key, so its rebind writes null
into the ticket element's `productTypeId`; the ticket validator rejects it.
Current review does not validate these references.

Evidence/reproduction:
`node /tmp/festapp-wizard-deep-20261021/matrix-ticket.mjs`,
`matrix-ticket.jsonl`. This is an authenticated SQL-boundary reproduction using
a real UI-produced replacement form; the ticket editor interaction itself was
not tested. All three cases rolled back.

Fix direction: reconcile inherited ticket bindings when replacing/deleting
form product types; preserve explicit user choices and validate before review.
Do not loosen the layout validator or silently remove ticket content.

## 6. Program copy drops capacity, visibility and grouping

Rollback-only fixture: a source program event with capacity 23, hidden=true,
group-event=true and split-for-men/women=true. Source manifest and finalization
were exercised with `copyProgram=true`.

| Setting | Source | Finalized program event |
| --- | --- | --- |
| `max_participants` | 23 | null |
| `is_hidden` | true | false |
| `is_group_event` | true | false |
| `split_for_men_women` | true | false |

Cause: `sources.sql` exports only title, start/end times and description for
program events. `finalize.sql` inserts only those fields. The ordinary existing
`database/functions/others/duplicate_occasion.sql` preserves these settings;
the wizard's copy boundary does not.

Evidence/reproduction: `node /tmp/festapp-wizard-deep-20261021/program.mjs`,
result `program.json`. Source fixture and diagnostic event were rolled back.
The copied occasion itself remained hidden and closed; this does not establish
live public disclosure, but the copied program event lost its hidden flag.

Fix direction: preserve supported program configuration and its relationships,
with an explicit policy for any intentionally excluded fields. Keep participant
signups and other runtime state out of the copy.

## Passing controls and remaining limits

- Unchanged copy after the original occupancy fix: one blueprint, 182 seats,
  schema-3 ticket, closed/hidden result.
- Ticket explicitly disabled stayed disabled in the finalized copy.
- A valid custom ticket product binding remapped correctly with its original
  form; the form-only replacement passed when the inherited ticket was absent.
- Actual UI source changes Skautsky ples -> Skautsky tabor -> From scratch
  cleared inherited seat objects and restored the appropriate source/default
  form and ticket settings. From scratch removed the inherited ticket entirely.
- Actual UI blueprint Inherit -> New reset objects/groups/background and size to
  12 x 8; returning to Inherit restored 182 seats, 32 x 32 and source background.
- The restored background rendered correctly in a fresh browser with real seat
  positions and product prices. Screenshot: `restored-blueprint.png`.
- A form-disabled probe against this seed still materialized a default form.
  Investigation showed the seed organization's `IS_APP_SUPPORTED` is false,
  while compiled `AppConfig.isAppSupported` is true. The canonical creator
  intentionally forces forms for ticketing-only organizations. This probe is
  **not classified as a product defect** without aligned tenant configuration.
- An empty selected New blueprint was accepted by direct SQL, but UI review
  already rejects it. This API behavior was not promoted to an additional
  user-facing defect.

No drag operations, live ticket PDF preview, organization verification or
ticketing-only UI variant were covered. Findings 4-6 are SQL-boundary evidence,
not claims that every intervening browser/editor interaction was exercised.

The synthetic source rows and failed UI drafts were retained in the disposable
local backend for repair. Source rows from the initial QA were not edited by
this session. The backend can be restarted without resetting data. Product fixes
remain a separate task; the original repair handoff did not include these six
new cases.
