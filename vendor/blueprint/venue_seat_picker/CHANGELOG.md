## 0.4.4

- Keep custom tabletop labels inside the filled shape, including cutouts and holes, across editor previews and exported scenes.

- Remove fixed table chairs from the explicitly requested side while preserving other sides and protected seats.
- Support Flutter 3.44 / Dart 3.12 using compatible standalone Material UI releases, while retaining the current development toolchain.
- Remove unused direct Cupertino and Flutter localization declarations; required localization remains available through Material UI.
- Allow compatible shared-core crypto and XML versions; retain the converter version required by existing SVG import receipts.
- Enforce minimum SDK and dependency-resolution endpoints in CI without changing color selection, SVG backdrops or public widget APIs.

## JavaScript 0.3.8

- Rebuild the shared kernel from core 0.2.3 with the fixed requested-side chair removal and tested crypto/XML dependency ranges.
- Retain the public JavaScript API and browser requirements.

## 0.4.3

- Group total seat-count minus/plus controls inside the field, matching side counts, and visibly dim unavailable actions.
- Keep single-finger workspace panning responsive and transfer two-finger input to pinch navigation without applying camera movement twice.
- Preserve the opposite table edge during resizing, including rotated nesting and canvas boundaries.
- Reflow free chairs after footprint edits while preserving explicit side pins and protected seat identities.
- Keep one undo entry per resize and reuse immutable spatial indexes during preview.

## JavaScript 0.3.7

- Apply the shared CSS-pixel seat tap allowance without changing pointer-down or drag ownership.
- Keep unavailable seats in hit testing so nearby taps cannot jump across them.

## 0.4.2

- Keep imported tables editable when their legacy metadata also marks them as decoration.
- Keep seat-count digits visible beside compact circular controls in narrow localized inspectors.

## 0.4.1

- Keep seat-count edits within physical and reservation constraints while allowing temporary empty fields and multi-digit input.
- Add circular minus/plus controls to each table side and preserve pending edits when stepping.
- Recheck host-owned reserved and blocked seat identities before each change; allow adding and removing free seats where feasible.

## 0.4.0

- Migrate Flutter UI types together to material_ui/cupertino_ui on stable Flutter 3.47.7.
- Keep external flutter_colorpicker behind an explicit SDK Material compatibility boundary.
- Preserve current layout/resource/kernel and reservation contracts.
- Incorporate shipped host fixes for the public template gallery, clipped palette previews and CSS-pixel seat tap allowance into their canonical owner.

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
