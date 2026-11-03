## 0.2.5

- Derive open-path hit segments from rendered arrowheads, including their configured length and separate subpaths.
- Index rendered closed contours with stroke padding and measure selection margins from their visible strokes.

## 0.2.4

- Place custom-table labels and their measured ink within the filled tabletop, including shapes with cutouts and holes.
- Keep native text previews and compiled scenes aligned with the shared placement geometry.

## 0.2.3

- Remove surplus fixed chairs on the explicitly requested side, preserving other sides and protected identities.
- Allow compatible crypto updates and XML 6.6.1-7.x within the selected compiler's supported range.
- Retain the SVG compiler pin because public import receipts identify that implementation exactly.
- Update the test-only lower bound so downgraded test tools remain compatible with supported Dart SDKs.
- Retain Dart 3.10 support and verify minimum dependency resolution in CI.

## 0.2.2

- Add `LayoutSpatialIndex.resolveTap` and `LayoutTapDisposition`: exact targets
  before nearest outlines, an 8 logical pixel tap radius in Flutter consumers,
  and mode-specific blocking/ignored targets without bypassing availability.
- Keep tap tolerance separate from pointer-down/drag ownership, preserve Shift
  selection and tooltips, and cancel edits throughout pinch/cancel sequences.

## 0.1.0

- Initial immutable sparse document model and validation.
- Shared deterministic geometry, glyph display lists, generators, motion and JavaScript kernel.
