# Overview section hierarchy and empty note - 2026-11-02

User-requested refinement during the approved order-switching release. Astra Medium grouped customer identity, contact and notes on one subdued surfaceContainerLow surface with existing 16px padding and an 8px radius. Payment and contents retain their existing rendering; a 28px gap separates the customer group from contents. This is one group, not a repeated card stack, and introduces no new copy/icons/actions.

The existing InlineOrderField note-editor presentation omits its empty hint, so an empty editable hidden note has a single label and a blank body. Its readonly fallback, permissions, direct typing, draft registration, Save/Discard and other inline hints are unchanged. No new component option/API was added.

54 targeted presentation/save tests passed. New assertions cover null hintText, empty controller and absent Bez poznámky in writable light/dark cases. Targeted analyzer reports no errors/warnings, with 11 existing informational diagnostics. Astra and primary inspected native dark/narrow, light/readonly wide, mobile 1.6x text and dirty-note Save/Discard captures. Baseline and final captures are retained privately under /tmp/festapp-overview-hierarchy-20261102/{before,after}; selected synthetic final captures are included here.

This UI change layers on main 310c227077c155be6d12e6825d5605f732978e01. The already-authorized performance migration 20261102180000 was independently applied and verified while the frontend release was held for this refinement. No additional migration is needed and the existing migration must not be replayed. Include this UI commit and the performance changes in the single pending prod/festapptickets release.
