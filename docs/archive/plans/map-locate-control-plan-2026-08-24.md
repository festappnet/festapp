# Off-screen current-location indicator

Date: 2026-08-24
Status: Implemented
Verification profile: standard

## Final outcome

The map uses one renderer-neutral current-location contract on every supported
map renderer:

- When the user is inside the visible map area, the renderer's ordinary current
  location puck is shown and the edge indicator is absent.
- When the user is outside the visible map area, a flat blue drop appears at
  the exact usable edge in the geographic direction of the user.
- The drop moves continuously along all four edges, including both bottom
  corners, as the camera moves.
- The drop does not overlap edge-adjacent map controls. Controls reduce the
  usable map rectangle only on the edge where they occupy the least map area.
- Tapping the drop recenters the map through the shared locate and viewport
  coordinators.
- The previous permanently visible locate button is removed.

## Architecture

- `MapPage` is the sole owner of the Dart location stream and the locate action.
- `MapLocationAccuracy` provides the shared permission and position boundary.
- `MapLocateCoordinator` coordinates a locate request without knowing a map
  renderer.
- `MapViewportCoordinator` remains the renderer-neutral camera boundary.
- `MapScene.currentLocation` supplies the position to the legacy renderer;
  MapLibre keeps its native current-location puck.
- `MapOffscreenLocationIndicator` owns visibility and presentation of the edge
  drop.
- `MapEdgeIndicatorLayout` owns the pure geometry: viewport projection, usable
  rectangle calculation, and ray/edge intersection.
- `MapLocationStyle.color` is the single shared blue used by the native puck and
  the edge drop.

This keeps location acquisition, map-camera control, geometry, and painting in
separate small modules. Neither renderer owns a duplicate locate workflow.

## Geometry contract

1. Project the current geographic position into viewport coordinates.
2. If the projected point lies in the current usable viewport, hide the drop.
3. Build one usable rectangle from edge-adjacent occupied rectangles.
4. Cast a ray from the usable rectangle's center toward the projected point.
5. Place the drop so its tip meets the intersected usable edge exactly.

The calculation does not switch independently between left/right candidates at
corners. A single ray intersection therefore preserves continuous movement on
the top and bottom edges.

## Canonical removal

The obsolete fixed-control implementation and its widget test were deleted.
There is no renderer-specific locate button and no second location stream in a
map surface.

## Validation evidence

The implementation was exercised in the real CSM Ostrava application on an iOS
simulator, including camera movement through the top and bottom corners and
interaction with floating map controls.

Targeted automated checks:

```bash
fvm flutter test \
  test/components/map/map_edge_indicator_layout_test.dart \
  test/components/map/map_offscreen_location_indicator_test.dart \
  --reporter compact

fvm dart analyze \
  lib/components/map/map_edge_indicator_layout.dart \
  lib/components/map/map_offscreen_location_indicator.dart

git diff --check
```

The geometry suite includes an angle sweep across both bottom corners and an
assertion that the tip has no artificial edge gap.

## Deliberate platform state

The repository remains on Flutter 3.47.2 through the canonical project config
and its generated FVM pins. The accompanying analyzer
and iOS dependency adjustments are part of that supported toolchain state and
must not be reverted as part of this feature.
