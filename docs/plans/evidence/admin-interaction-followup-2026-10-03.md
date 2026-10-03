# Administration interactions and preserved presentation

## Bank edit click

The native empty list route was painted above the persistent bank list. Its
navigator absorbed pointer events, so the visible pencil never received clicks.
The new regression taps a list edit button through BankAccountsNavigationView
and the real native push, rather than opening a detail deep link directly. It
failed with a hit-test warning and no Dialog. IgnorePointer on the empty native
list route lets the underlay receive clicks; detail routes retain normal input.
The regression opens, closes and reopens the compact dialog and its general tab.
The fixture also now mirrors production's empty initial route and general redirect.

## Form appearance

Restored the presentation from immediately before tab deep links: 44px toolbar,
left-aligned 16px labels, article icon, muted slash, themed foreground color,
original unfold selector with selected-item checkmark, and Create action. Removed
the extra leading Back arrow and centered default-size header. The original
form/editor/settings/design/responses TabBar presentation was already identical
and stays intact. Create/copy calls share the original workflow through
FormCreationHelper; routed actions continue to respect the retained-draft guard.
The form breadcrumb still returns to the explicit list and preserves its query.

## Repeated failed context loads

A delayed access response with no resolved occasion/unit metadata notified the
context listener and threw. The listener then automatically loaded the same
failed context again every frame. Both occasion and unit regressions reproduced
repeated requests instead of one. Failed loads now stop automatic retries until
an explicit retry or a new route load. Retained content stays hidden on failure,
with the failure screen taking precedence over a context-mismatch spinner.
The occasion regression additionally restores the loader and verifies explicit
Retry succeeds; prior rights-revocation/restoration and browser-history tests pass.

## Tab transitions and occasion switching

Restored AutoTabsRouter.tabBar's native animated transition, matching the previous
TabBarView. Occasion switching now carries the active static section/subtab paths,
including Report and Orders/History, from the active native router even when the
breadcrumb context belongs to the outer shell. Object IDs and their queries do
not cross occasions; a form detail returns to Forms for the destination occasion.
Existing feature availability normalization still chooses an available tab.
Tests cover Report switching, object-ID removal, and History A -> B -> A with Back.

Validation: 102 navigation/unit widget tests pass. Scoped Dart analysis reports
no errors or warnings. Shared source is validated on main; the local preview
keeps its report work and tenant configuration, and is rebuilt into staging before
replacing the existing compiled server root on port 18875. No duplicate user-facing
Flutter server is left running. Live rollout is only prod/festapp.
