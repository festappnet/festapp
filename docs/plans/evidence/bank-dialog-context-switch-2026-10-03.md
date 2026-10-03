# Bank dialog and breadcrumb context switching

The existing-account editor again uses a compact dialog (maximum 600 x 800),
with a root overlay above the whole application. The unit-scoped routes
`/unit/:id/edit/bank-accounts/:accountId/general|connection|users` retain their
URLs. The account list remains beneath the dialog, including direct entries.
Closing refreshes the list; button, barrier and Escape share the draft guard.
An inactive retained section hides the overlay without disposing its child
router, so restoring it retains the selected tab and draft. Creation still uses
its original transient dialog. Unit/account membership checks remain in place.

The organization breadcrumb loop was reproduced through the actual
`RouterService.navigateToUnitAdmin` caller and `UnitAdminPage`: switching from
unit 1 to unit 2 produced `[1, 2, 1, 2, ...]` loads across successive frames.
AutoRoute `RouteData.isActive` checks only the route name, so both retained
instances treated themselves as current. Boundaries now compare the native
match ID with visible URL-state segments. IDs survive native match copies;
comparing complete matches is unsuitable when child stacks change. Native
modal-route activation also triggers context restoration when Back reveals a
retained page. The unit access adapter keeps the same production RightsService,
authentication and occasion-list calls and enables deterministic caller tests.

Validation: 95 targeted navigation/unit tests passed, covering full-screen
modal bounds, direct account tab URLs, close button/barrier/Escape, cancelled
draft dismissal, inactive overlay restoration, foreign-account rejection,
breadcrumb switching and Back. The unit-switch test also verifies access
revocation and restoration. Targeted Dart analysis has no errors or warnings;
existing style infos remain. Generated AutoRoute code was regenerated normally.
These are widget/router checks with injected backend data, not production writes.

Reusable findings were added to the canonical festapp-local-e2e skill and its
installed symlink; skill validation passed.
