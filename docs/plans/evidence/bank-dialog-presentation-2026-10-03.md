# Bank account dialog presentation and loading

The routed bank subtabs used the generic administration tab style, replacing the
original equal-width text tabs with icons and an administration background.
Restore the bank dialog's original TabBar, label color and animated tab content.
Add a localized close icon to both routed edit and ordinary creation headers.
Close, Cancel, Escape and barrier dismissal use the existing discard guard.

Previously the loading route and loaded editor owned different overlay portals;
loading completion destroyed one dialog and mounted another. Keep one dialog at
the detail route boundary and replace only its content, preserving the overlay.
Saved account changes also update the retained header without replacing the editor.

The unit underlay and detail now share one initial unit-account future. Mutations
refresh it; closing detail invalidates it and remounts the list once. Remove the
second list refresh formerly attached to the completed route-push future.
The cache belongs to the unit navigation instance and resets when its unit changes.

Validation: 103 targeted navigation/unit tests pass; scoped analysis has no errors
or warnings. A delayed load test verifies one request, identical dialog State
before/after completion, original text-only equal-width tabs, header close, and
exactly one list refresh. Existing draft-cancellation, Escape, barrier, browser
history, Save and retained-tab tests still pass. Shared changes land on main and
only prod/festapp; localhost 18875 preserves its separate report edits/profile.
