# venue_seat_picker

Interactive venue seat maps for Flutter: a zoomable viewer, optimistic
reservation picker and grid editor behind one consistent model seam.

Built for and used in production by [Festapp](https://festapp.net), including
the live application at [live.festapp.net](https://live.festapp.net).

[Try the live interactive picker and editor demo](https://festappnet.github.io/venue_seat_picker/)

![Slower close-up of seat selection and venue editing](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/demo.gif)

[Watch the higher-quality close-up WebM demo](https://github.com/festappnet/venue_seat_picker/raw/main/doc/demo.webm)

| Customer picker | Venue editor |
| --- | --- |
| ![Selecting seats in a compact theatre](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/picker.png) | ![Editing seats in the same compact theatre](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/editor.png) |

The picker and editor operate on the same controller and venue document, so an
application can offer customer selection and staff editing without maintaining
two layout implementations. The media above uses a small fictional theatre so
individual seat states and interactions remain easy to follow.

## Touch selection

Grid and object surfaces resolve completed taps with an 8 logical pixel radial
margin, independent of camera zoom. Exact targets win; otherwise the nearest
real outline wins in paint order. Availability and pending targets stay in the
resolution so an unavailable seat cannot select a farther free seat. Existing
handlers own feedback, reservation and rollback; semantic seat activation uses
the same handler as coordinate taps.

In the object editor, Select touch drags beginning on empty space pan the
viewport, while mouse drags keep marquee selection. Exact object/handle drags
and drawing tools retain their editing behavior. Two fingers own navigation
until the entire pointer sequence ends; cancel restores an unfinished edit.
Tap tolerance does not acquire object or handle drag ownership.

## Features

- Zoom, pan and automatic fit-to-viewport.
- Optimistic async selection with rollback and duplicate-tap protection.
- Selection limits, pending indicators and custom eligibility rules.
- Grid editor with immutable create/update delegates.
- Custom seat builders, tooltips, colors and SVG/image backdrops.
- Native light and dark mode support through
  `VenueSeatViewConfig.fromTheme(context)`.
- Versioned JSON through `VenueSeat` and `VenueSeatDocument`.
- Read-only `SeatAdapter`; the package never mutates your domain objects.
- Android, iOS, Linux, macOS, web and Windows support.

## Quick start

```yaml
dependencies:
  venue_seat_picker: ^0.1.1
```

```dart
final seats = [
  const VenueSeat(id: 'A1', position: SeatPosition(0, 0), label: 'A1'),
  const VenueSeat(id: 'A2', position: SeatPosition(0, 1), label: 'A2'),
];

final controller = VenueSeatController<VenueSeat, Object>(
  adapter: venueSeatAdapter,
)..loadPlan(rows: 4, columns: 8, seats: seats);

VenueSeatPicker<VenueSeat, Object>(
  controller: controller,
  maxSelectedSeats: 4,
  onSelectionRequested: (request) async {
    return request.selected
        ? reservations.hold(request.seatId)
        : reservations.release(request.seatId);
  },
  onSelectionChanged: (selectedIds) {
    debugPrint('$selectedIds');
  },
)
```

The viewer, picker and editor keep the plan visible during zoom and pan by
default, centering any axis that fits inside the viewport. Use
`VenueSeatViewConfig(boundaryMargin: EdgeInsets.all(24))` for a small edge
allowance, or explicitly pass `EdgeInsets.all(double.infinity)` to allow
unrestricted panning.

Create the controller in `State.initState` and dispose it with its owning
widget. The runnable [example application](example/) and its
[live web version](https://festappnet.github.io/venue_seat_picker/) demonstrate
selection, pending state, zoom, local SVG/PNG/JPG backdrop selection, bounded
panning, status rendering and live layout editing. Selected files stay in the
browser and are not uploaded. The example follows the device's light or dark
appearance automatically.

## Use an existing domain model

Map it through a read-only adapter. Pricing, authorization, persistence and
reservation locking remain in your application.

```dart
final adapter = SeatAdapter<MySeat, int>(
  idOf: (seat) => seat.id,
  positionOf: (seat) => SeatPosition(seat.row, seat.column),
  statusOf: (seat) => switch (seat.status) {
    MyStatus.free => SeatStatus.available,
    MyStatus.held => SeatStatus.held,
    MyStatus.sold => SeatStatus.booked,
  },
  labelOf: (seat) => seat.label,
  groupOf: (seat) => seat.sectionId,
);

final controller = VenueSeatController<MySeat, int>(adapter: adapter)
  ..loadPlan(rows: venue.rows, columns: venue.columns, seats: venue.seats);
```

Current-user selection is an optimistic UI overlay, not a `SeatStatus`. This
keeps the package from writing transient state into your authoritative model.

## Editor

```dart
VenueSeatEditor<VenueSeat, Object>(
  controller: controller,
  editing: SeatEditingDelegate(
    create: (position, status) => VenueSeat(
      id: '${position.row}:${position.column}',
      position: position,
      status: status,
    ),
    withStatus: (seat, status) => seat.copyWith(status: status),
  ),
  onChanged: saveDraft,
)
```

## Guides

- [Getting started](doc/getting-started.md)
- [Backend integration](doc/backend-integration.md)
- [Editing and JSON](doc/editing-and-serialization.md)
- [Theming and custom rendering](doc/theming.md)

## Contract

- Rows, columns and seat size must be positive.
- Seat IDs and positions must be unique and inside the venue grid.
- Missing positions are empty slots, not a seat status.
- Shrinking refuses to clip occupied slots.
- Only `available` seats can be selected; selected seats can be released.
- A rejected or failed request restores the previous optimistic selection.

Flutter 3.32+ and Dart 3.8+ are supported. The package intentionally has no
backend or state-management dependency.

See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the
[issue tracker](https://github.com/festappnet/venue_seat_picker/issues).

Licensed under the MIT License.

## Object layout editor (0.2)

The additive object API keeps the existing grid API available. Geometry lives in
`venue_layout_core` and compiles to the browser kernel used by the JS SVG viewer.
No backend, login or Festapp checkout is required.

```dart
import 'package:venue_seat_picker/venue_seat_picker.dart';

final resources = await loadLayoutFixtureResources();
final controller = VenueLayoutController(
  VenueLayoutTemplates.create('ball-classic'), resources: resources);
// Place in a bounded area of your app:
VenueLayoutEditor(controller: controller);
// Dispose the controller when its host closes.
```

Nine editable templates ship in the public package, with fresh UUIDs per use:
classic ball (72), round tables (80), mixed ball (68), balcony hall (64), lounge
(12 seats plus standing capacity supplied by the host), auditorium (120), bus
(45), two train cars (48), blank (0). Use `VenueLayoutTemplates.all` for metadata,
`byId(id)` or `create(id)` for instances. The editor gallery uses this same API.

`VenueLayoutViewer` consumes the shared display list. `VenueLayoutPicker` adds
async selection callbacks, indivisible selection units and host-supplied standing
quantities. A rejected/failed callback restores the previous selection.
Resources, seat prices/status and standing availability belong to the host.
`LayoutFontProvider` and `LayoutAssetProvider` define provider boundaries;
`loadLayoutFixtureResources` is an optional licensed local example provider.
Unsupported fonts/glyphs produce visible resource issues, with no font download.
`VenueLayoutStrings` can resolve the default English UI strings for a host.

Import `package:venue_seat_picker/editor_ui.dart` for the shared editor controls:
`EditorColorDialog`, `EditorColorSwatch`, and `EditorFontPicker`. These same
widgets serve the venue and Festapp Ticket editors. Hosts supply font metadata,
resource loading, color validation, localization and undo transactions. The
controls have no dependency on venue geometry or ticket models. See
[the shared UI boundary](doc/blueprint-v2/EDITOR-UI.md).

`VenueLayoutController` owns draft history, gesture begin/preview/commit/cancel,
selection and read-only enforcement. `LayoutHistoryParticipant` joins external
draft metadata to the same undo transaction. Save confirmation closes history on
a new baseline; undo is never a server transaction. Pass additional inspector UI
through `inspectorBuilder`; it must not reimplement geometry.

See [example/README.md](example/README.md) for the standalone editor/demo kit,
[the canonical document schema](doc/layout-v2.schema.json),
[core operations](doc/blueprint-v2/CORE-API.md), and [JS usage](web/README.md).
Only package/demo stage A is implemented here; reservations, SQL atomics,
permissions, payments and production font/image adapters remain host integration.
No registry publication or demo deployment is performed by the local build.

### Localization

The package ships English (default/fallback) and Czech messages through Flutter
localization delegates:

```dart
MaterialApp(
  locale: const Locale('cs'),
  supportedLocales: VenueLayoutLocalizations.supportedLocales,
  localizationsDelegates: VenueLayoutLocalizations.localizationsDelegates,
  home: const MyEditorPage(),
)
```

`VenueLayoutLocalizations.of(context).text(message)` resolves package messages;
`table`, `couch`, and `tableName(number)` expose common object names.
`VenueLayoutStrings(resolve: hostResolver, child: editor)` remains an optional
host terminology override, so Festapp can use its own translation catalog.
Unknown messages fall back to their English source. The combined delegate list
also includes Flutter Material, Widgets and Cupertino localization delegates.

Create localized stock content explicitly, keeping user-authored labels intact:

```dart
final strings = VenueLayoutLocalizations.of(context);
final document = VenueLayoutTemplates.create('ball-classic', localize: strings.text);
final controller = VenueLayoutController(document, tableLabelPrefix: strings.table);
```

`localizeLayoutDefaultLabels(document, strings.text)` updates known stock labels
in an existing draft without changing IDs, level identities, parentage or custom
names. Structural columns and minor decorative objects have no default visible
name. Node text and localized section titles travel with the portable document,
so the web preview displays the same labels as the editor.

On desktop, ordinary wheel scrolling zooms around the pointer, even with a
selection. Shift-wheel pans horizontally; trackpad pan/pinch gestures and the
hand tool remain available. Ctrl/Cmd-drag copies the selected assembly; insertion,
clipboard paste and duplication allocate unused table numbers. A copy drag is a
single undo transaction, and Escape/cancellation removes the provisional copy.


Selected row assemblies expose row and seat-column counts directly in the
inspector, with add/remove buttons and numeric input. Advanced settings include
curvature, seat spacing, row spacing, blocks and aisle width. Changes preserve
existing seat IDs by semantic slot and are individually undoable. Row generation
persists all layout settings and derives chair rotation from the curve tangent
in world units. `rowLayoutParameters(document, rootId)` recovers settings from
older materialized rows; `repairLegacyRowTangents(document)` explicitly repairs
matching legacy generator angles without replacing manual or locked placements.


Curvature is directly editable with a number and slider; a slider gesture is
one undo transaction. Drag a palette chair or a standalone chair over a table
to attach the same seat identity to it. Hover highlights the target and a full
table rejects the drop without leaving an orphan chair.

Open paths use an 8-screen-pixel editor hit target, selectable line endpoints
and polyline vertices. Endpoint edits normalize geometry bounds and resizing
scales actual path points. Finished lines/paths are selected automatically and
insertion returns to the selection tool. Stroke color and width are available
directly in the inspector.

Row assemblies can be selected in the gaps between chairs and resized with all
eight handles. Resizing changes spacing and curvature while retaining chair
size, IDs and undo history. Selection feedback starts on pointer-down; double
click still edits labels or the canvas. Selection-only changes do not resave the
portable demo bundle.

Table attachment reserves manual and locked chair footprints and prevents new
chair-chair and chair-table intersections. The hover target uses the same atomic
feasibility check as attachment; impossible drops leave the document unchanged.

Round tables keep their aspect ratio during ordinary resizing; hold Shift to
make an ellipse. Shrinking tables removes only surplus free seats in the same
undo transaction. Supply the controller's live `protectedSeatIds` callback for
booked, reserved and blocked seats; these IDs cannot be removed by a resize,
count edit, generic edit, undo or redo. Commercial state stays in the host.

Table chairs redistribute at every canvas wall and corner when they physically
fit. Dragging an individual attached chair near a standard free perimeter slot
snaps its position and orientation on release (Alt or disabled snapping bypasses
this). Drag previews contain only the centered object on transparency.

The inspector follows selection: changing objects resets its scroll position and
leads with that object's editable properties. Canvas/background/preset controls
appear when no object is selected. Selecting multiple objects exposes common
actions. Shift-click toggles membership, Shift-marquee adds to the selection,
and dragging an already selected member moves the whole set as one undo step.

Couches have real cushion seats, arms and a backrest, with no painted furniture
name. Their inspector edits seat count; resizing redistributes cushions while
retaining IDs. Atomic couch membership cannot change once any member is host
protected. All rectangular table aliases use the same default corner radius;
explicit zero still produces square corners.

For lines/arrows and regular zigzags, click start then end or drag. Zigzags have
inspector controls for tooth count and peak-to-peak height, two endpoint handles
and one hollow height handle. Straight lines remain straight. Polygons accept
successive clicks, Enter/double-click to finish and Backspace to remove the last
point. Escape cancels; Shift constrains drawing to 45-degree steps. Existing
freeform polylines retain vertex editing. Each gesture has one undo step.

Couch count changes now preserve cushion width in both directions: adding then
removing the same places restores the previous body length. Wall reflow centers
regular rectangular side rows, including already-contained uneven wall drafts,
while retaining locked/manual exceptions and the fixed canvas.

The editor accepts an optional `onImportBackground` async host callback, exposed
directly in the background inspector. The host owns file picking, image decoding
and portable resource registration; the demo wires its existing bounded import.
Canvas color is visible without expanding settings. Shared color dialogs receive
colors used in the layout plus the decoded background for artwork suggestions.
Table/assembly seat fills are editable together as one undoable change; multi
selection supports a shared fill edit. Palette previews are suppressed outside
the actual canvas and outside drops leave no history entry.

Drag feedback renders canonical geometry at the current canvas zoom, preserving
the same origin as placement even for asymmetric/rotated assemblies. A stable
per-drag fragment survives gray-area crossings; outside previews remain hidden.
The inspector exposes named color styles and independent custom colors. Right
click or touch long press opens object actions, including a style dialog and
copy/paste style. Style transfer excludes geometry, labels and identities, respects
locked ancestors, and commits one undo step. Browser context-menu suppression
is scoped to the interactive editor canvas and is removed on disposal.

The editor's Grid toggle (G while canvas has focus) is independent of snapping.
It uses the same world-origin eight-unit lattice and displays coarser multiples
at low zoom to avoid moire. Grid strokes stay constant in screen pixels, are
clipped to the visible canvas, and paint above the background image and below
objects. This editor-only overlay does not change documents, history or exports.

Plan style is shared by object kind (tables, seats, shapes, couches, standing
areas and text). The document stores its global palette, stroke widths, opacity
and corner radii; existing and future nodes inherit without materializing copies
on each node. Local edits mark explicit property overrides, and Use plan style
restores inheritance for the selected assembly. Presets apply across the whole
plan as one undo step. Palette previews, drag feedback, inline text, native
rendering and the JS viewer all resolve the same canonical appearance.

The default inspector prioritizes seating and geometry. Per-object appearance is
collapsed; shared plan styles remain primary and their presets show color swatches.
Canvas size, canvas color and background-image controls share one Canvas section.
The current demo does not expose a reusable-object library or demo-price editor.
Duplicate/delete remain available; grouping actions appear only for relevant
selections. Existing portable preset/price data is retained unchanged.

Global color palettes and appearance are separate controls. Color palettes change
fill/outline/text colors and canvas background while preserving chair material,
corner radii, opacity and stroke widths. Chair appearance supports plain, shaped
wooden construction and rounded upholstery, retaining the same seat identity and
a canonical hit contour matching the silhouette. Miniature preset previews use the canonical scene renderer.
Canvas settings start collapsed; double-clicking empty canvas opens them for
editing. Automatic seat filling is no longer exposed in this editor.

Global Appearance offers three coordinated families (Modern, Timber, Lounge)
with canonical chair/table/couch previews. Families change silhouettes and
construction as well as outline/corner treatment, independently of the color
palette. Object-specific numeric controls are under Fine-tune appearance.
