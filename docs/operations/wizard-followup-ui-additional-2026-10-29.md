# Additional wizard exploration and mobile navigation - 2026-10-29

Continuation of [wizard/editor parity QA](wizard-followup-ui-2026-10-29.md).
The user authorized continuing exploration and integration through the other
session's release owner. This session owns the isolated branch
`wip/blueprint-active-20261029`; it does not merge or deploy independently.

## Additional completed scenarios

- Reopened retained draft E in the real compiled Flutter application using an isolated local browser. Existing title and selected question survived.
- Aborted only the browser's `save_occasion_setup_draft` HTTP transport, then typed `QA parity E offline retained`. UI displayed the save error and Retry, retaining the exact unsaved input. Readback still showed the earlier title, confirming it had not been persisted.
- Removed the abort route and clicked Retry. The error disappeared and authoritative readback returned revision 11 with the exact new title. No database fixture edits were used to produce the result. [Unsaved input retained](wizard-followup-ui-2026-10-29/offline-retained.png).
- Resized the actual wizard to 390 x 844. Found that completed/upcoming questions became inert progress markers, with no accessible replacement for desktop question navigation. The active question label was also inert. Source retained an unused menu-label property and a comment referring to a nonexistent menu. [Before](wizard-followup-ui-2026-10-29/mobile-navigation-before.png).

## Fixed: mobile question navigation

The active question pill now opens a menu when individual question buttons do
not fit, or enlarged text suppresses those buttons. The menu lists every
question, including optional sections, with the existing numbering and state.
It delegates selection to the same existing callback as desktop navigation.
The trigger has a 48 px minimum height and a downward chevron. Its default
tooltip follows the UI locale through Material localizations. Desktop question
buttons keep their existing behavior.

A new regression first failed on the missing trigger. The final story-shell
suite passed all 11 tests, including the actual menu selection at 390 px,
optional unnumbered targets, desktop keyboard navigation and existing
320/375/812/1440 px layouts. Targeted analysis has no errors or warnings and one
preexisting informational lint. The Impeccable mechanical detector returned
no findings. Existing styles were retained.

## Limits and handoff

- The previous gallery fix is checkpoint commit `b659969e6`. Source inputs and evidence were preserved in the isolated worktree.
- Date/time pickers and the ticket-delivery dropdown still could not be reliably driven in this Flutter release browser fixture. Exploratory native CDP clicks, temporary semantics-overlay hiding and scrolling were attempted; no successful date/time or inline/both-delivery scenario is claimed. Temporary browser DOM changes were restored. This is an automation limit, not a proven product defect.
- Existing local font/Edge configuration still limits full PDF validation. Real payments, email delivery, invitation delivery, OAuth and organization verification remain outside this local proof.
- This is bounded additional exploration, not a claim that every UI combination has been tested. Final integration and production release belong to the coordinated release session.

## Final real UI verification

The final release-mode app compiled successfully in 108.9 seconds. At 390 x
844, new draft G displayed the localized Show menu trigger. Its menu listed all
15 current destinations, including the optional Team and Verification sections.
Selecting Verification displayed that section and persisted
`storyQuestion=verification`. Reopening the menu and selecting Name restored the
name field; database readback retained `QA parity G mobile navigation` and
`storyQuestion=name`. [Menu](wizard-followup-ui-2026-10-29/mobile-navigation-menu.png),
[target section](wizard-followup-ui-2026-10-29/mobile-navigation-target.png),
[readback](wizard-followup-ui-2026-10-29/additional-readback.json).

The final UI build contains both local fixes. The final readback confirms zero
email messages, zero active cron jobs and a paused queue without a worker URL.
No source changes followed the passing targeted tests, analysis and final build
except formatting. The browser and owned local UI/backend processes were stopped
with QA data retained before handoff. The release owner receives the gallery
checkpoint plus this follow-up commit and performs integration/release.
