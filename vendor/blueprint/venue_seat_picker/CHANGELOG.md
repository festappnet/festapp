## Unreleased

- Keep single-finger panning from the workspace outside the plan responsive
  in navigation mode independently of ancestor gesture recognition. Transfer two-finger input to
  the existing pinch navigation without applying camera movement twice.

## JavaScript 0.3.6

- Add registry installation instructions and working public documentation links.
- Publish the existing successful main CI archive without rebuilding it.
- Recover an already-published archive with different gzip encoding only when
  its entire tar payload is identical, preserving the original registry bytes.

## 0.3.7

- Present the library as Venue Layout across the README, package descriptions,
  showcase and demo titles. Preserve the Flutter `venue_seat_picker` and
  JavaScript `@festapp/venue-layout` package identifiers.
- Explain the Flutter editor, shared geometry, JavaScript consumer and host-owned
  booking responsibilities in the public repository entrypoints.
- Follow BankSync's protected-tag and npm-environment OIDC release flow; remove
  the earlier inactive CI publishing path and require exact archive integrity on retries.

## 0.3.6

- Restore the current object-editor showcase README with six workflow GIFs,
  downloadable videos, the template gallery and current integration examples.
- Prepare npm trusted publishing from the verified CI archive, without a local
  login or a stored write token. npm account setup remains a one-time prerequisite.

## 0.3.5

- Add `LayoutSpatialIndex.resolveTap` and `LayoutTapDisposition`: exact targets
  before nearest outlines, an 8 logical pixel tap radius in Flutter consumers,
  and mode-specific blocking/ignored targets without bypassing availability.
- Keep tap tolerance separate from pointer-down/drag ownership, preserve Shift
  selection and tooltips, and cancel edits throughout pinch/cancel sequences.

## Unreleased production v2 fixes

- Preserve the opposite table edge while resizing, including rotated nesting and canvas boundaries.
- Convert free chair poses to automatic seating after footprint edits; preserve explicit side pins and protected seat identities.
- Keep one undo entry per resize and reuse immutable spatial indexes during preview.

## 0.3.1

- Restore the exact SDK fixes shipped in Festapp 35e421e27 to canonical source.
- Allow editor hosts to preview draft text with loaded fonts without enabling geometry editing. Canonical viewer rendering remains the default.
- Use the corresponding 0.2.1 core fixes and rebuild the 0.3.1 web distribution.

## 0.2.0 (unreleased)

- Add a backend-independent object layout document, controller and shared Dart/JS scene runtime alongside the existing grid API.
- Add an editor, viewer, async picker, public nine-template library and licensed local resource fixtures.
- Add standalone Flutter/JS demos, local export/import/autosave, reproducible kit tooling and explicit simulated host boundaries.
- Document schema 1 as a separate contract from VenueSeatDocument. Existing grid consumers remain supported; no automatic migration is performed.

## 0.1.2

- Keep zoomed plans visible by default in the viewer, picker and editor, center
  small plans, and update pan bounds when the viewport changes. Explicit infinite
  boundary margins retain unrestricted panning.
- Added in-memory image backdrops for local file previews and configurable pan
  boundaries.

## 0.1.1

- Removed visual grid lines from empty editor slots while keeping them tappable.
- Added native light and dark surface support through the host `ThemeData`.
- Improved the mobile demo with explanatory action captions.

## 0.1.0

- Initial release with `VenueSeatViewer`, `VenueSeatPicker` and
  `VenueSeatEditor`.
- Added a read-only `SeatAdapter`, immutable `VenueSeat` model, optimistic
  selection overlay, versioned JSON, custom rendering, theming, and tests.
- Extracted from and used in production by Festapp.
