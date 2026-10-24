## Unreleased

- Add `LayoutSpatialIndex.resolveTap` and `LayoutTapDisposition`: exact targets
  before nearest outlines, an 8 logical pixel tap radius in Flutter consumers,
  and mode-specific blocking/ignored targets without bypassing availability.
- Keep tap tolerance separate from pointer-down/drag ownership, preserve Shift
  selection and tooltips, and cancel edits throughout pinch/cancel sequences.

## 0.1.0

- Initial immutable sparse document model and validation.
- Shared deterministic geometry, glyph display lists, generators, motion and JavaScript kernel.
