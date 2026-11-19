# Default form closure at the end of the event

Date 2026-11-19. Verification standard because checkout and a forward database migration are involved.

## Outcome and contract

Forms without an explicit closing instant inherit the owning event's current end. Moving the event end moves the inherited cutoff. A stored custom cutoff can precede or follow the event end. Clearing it restores inheritance. The manual switch remains an independent control. Preserve the existing inclusive end boundary and the authorized exceptions for organizer orders and personal waitlist offers.

## Implementation

1. Resolve the inherited end in `get_effective_form_data` after normalizing the stored schedule. Its existing consumers cover the public form, registration mode, checkout, new seat holds, sale summaries and email scheduling. Keep the authored schedule sparse and retain all historical explicit dates, including dates equal to a past event end. The data provides no reliable way to distinguish those dates from intentional selections.
2. Keep the setup wizard's effective end for validation and persist only a submitted override. Add a read-only occasion end to `get_form_editor_bundle_internal` for the editor and save acknowledgement. Show that date with the existing localized hint whenever the override is absent. Keep the clear action for overrides and remove the start picker's automatic one-hour closing override.
3. After an event-end edit, refresh inherited forms in the existing notification projection under the occasion save's existing locks. Baseline inherited schedules silently in a forward migration so existing active projections get the new due time and past events do not generate activation-time notices. Assemble the migration from the current canonical SQL sources. Existing catalogue grouping by event date remains independent of the closing date for an individual form.
4. Extend registered SQL tests to verify the public and editor projections, inherited end boundary, rescheduling, explicit dates, wizard finalization and notification timing. Run the affected SQL cases on a disposable local database and analyze the edited Dart files. Check source/migration parity.

Completion means the same stored form follows both an earlier and a later occasion end, a custom value remains fixed, and clearing it follows the event again. The local change includes the forward migration. Production application and release require separate authorization.
