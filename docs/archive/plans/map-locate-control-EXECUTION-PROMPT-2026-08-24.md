# Off-screen current-location indicator — execution record

Date: 2026-08-24
Status: Completed; do not re-execute

The original execution prompt proposed a permanently visible corner control.
That proposal was superseded during implementation by the final user-directed
behavior: the renderer's normal current-location puck is visible in-view, while
a bare directional drop appears only when the user is outside the usable map
viewport.

The authoritative implementation record, architecture, invariants, removal
scope, and validation evidence are in:

`docs/archive/plans/map-locate-control-plan-2026-08-24.md`

Any future change must preserve the renderer-neutral ownership model, continuous
edge movement, exact tip-to-edge placement, avoidance of map controls, and the
single location stream owned by `MapPage`.
