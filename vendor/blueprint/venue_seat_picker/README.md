# Venue Layout

**Build the room. Pick the seat.**

A full-featured seating-plan editor, viewer and customer picker for Flutter and
the web. Design tables and custom layouts, arrange an entire venue, and let
guests choose their places from the same portable plan.

Built for [Festapp](https://festapp.net). Use it independently in your own app,
with your own backend, branding and booking flow.

Flutter package: `venue_seat_picker` · JavaScript package: [`@festapp/venue-layout`](https://www.npmjs.com/package/@festapp/venue-layout).

[Try the interactive demo](https://festappnet.github.io/venue_seat_picker/) ·
[Flutter package](https://pub.dev/packages/venue_seat_picker) ·
[JavaScript integration](web/README.md)

- **Create the whole venue:** tables, chairs, custom outlines, curved rows,
  standing areas, couches, buses and train carriages.
- **Edit faster:** drag and drop, animated chair layout, Ctrl-drag copies,
  multi-selection, shared styling and undo/redo.
- **Start with a template:** editable balls, halls, theatres, conferences,
  lounges and transport layouts, with fresh identities for every plan.
- **Let guests choose:** zoomable Flutter and JavaScript pickers, async selection,
  pending feedback, rejection rollback and standing quantities.
- **Make it yours:** light/dark themes, English/Czech localization, host-supplied
  availability and prices, and portable JSON with local font/image resources.

## What this repository provides

- **Flutter editor and picker:** `venue_seat_picker`, including the template
  gallery, editing controller, customer selection and native/web rendering.
- **Portable geometry:** `venue_layout_core`, the shared document, geometry,
  display lists and selection rules used by Flutter and the JavaScript kernel.
- **JavaScript viewer and picker:** `@festapp/venue-layout`, an SVG consumer for
  web applications that use their own backend and booking flow.
- **Runnable examples:** the Flutter studio, standalone JavaScript demo and
  recorded workflows below.

The package manages plans and selection UI. Your application manages live
availability, prices, reservation locks, orders and payments.

## Start with a ready-made plan

From halls and theatres to buses and train carriages, choose an editable starting
plan and adapt it to your event. Here is the development template catalog:

![Ready-to-edit venue templates for halls, cinemas, conferences and transport](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/template-library.png)

## See it in action

Six focused workflows, recorded on 21 October 2026 from the **0.3 editor** in
light mode with English captions. The hosted demo and registry releases are
updated separately.
[Video downloads and captions](doc/media/README.md).

### Place a table. Make it yours.

Drag a table onto the plan, add and remove chairs, then try a round shape.
Seats animate into place as you edit.

![Drag a table onto the plan and customize its chairs and shape](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/table-basics.gif)

### Build and style a whole row

Hold Ctrl to drag out copies. Select the row and give every table a coordinated
appearance in one step.

![Ctrl-drag copies and style the whole row together](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/copy-style.gif)

### Draw the table your room needs

Paint a connected custom outline, then click to add chairs one by one around
its perimeter.

![Paint a custom table and add chairs individually](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/custom-table.gif)

### Shape the audience around the stage

Drag curved seating into the center of the plan. Add or remove rows and columns,
adjust the curvature, then try selecting a place in the Flutter viewer.

![Drag an arc into the center, reshape the rows and try seat selection](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/arc.gif)

### Give transport its own style

Drag in a complete bus layout and switch to coordinated transport seating with
a different palette. Ready-made components can match your application.

![Style a ready-made bus with coordinated transport seats](https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/bus.gif)

### Choose places. Review tickets.

Follow the complete mobile flow: zoom into the plan, choose seats, check the
count and price, then review the selected places in one clean summary.

<img src="https://raw.githubusercontent.com/festappnet/venue_seat_picker/main/doc/media/mobile-order.gif" width="390" alt="Choose seats and review the selected places and total on a phone">

## Start building

Add the package to your Flutter application's `pubspec.yaml`:

```yaml
dependencies:
  venue_seat_picker: ^0.3.7
```

The object API uses `VenueLayoutController`, `VenueLayoutEditor`,
`VenueLayoutViewer` and `VenueLayoutPicker`. Flutter and the JavaScript SVG
consumer share the Dart layout core for geometry, scene rendering and hit tests.

```dart
import 'package:venue_seat_picker/venue_seat_picker.dart';

final resources = await loadLayoutFixtureResources();
final controller = VenueLayoutController(
  VenueLayoutTemplates.create('studio-tables'),
  resources: resources,
);

// Place inside a bounded widget, such as Scaffold.body.
VenueLayoutEditor(controller: controller);
// Dispose the controller when its owning State closes.
```

To try the object editor from this repository:

```sh
git clone https://github.com/festappnet/venue_seat_picker.git
cd venue_seat_picker
fvm install
python3 tool/configure_workspace.py
fvm flutter pub get
cd example
fvm flutter pub get
fvm flutter run -d chrome
```

The source checkout resolves its layout core locally. Use
`VenueLayoutTemplates.all` to discover templates and `create(id)` to create a
fresh plan. The [full example](example/README.md) includes the template gallery,
autosave, portable import/export and Flutter/web previews.

For a read-only view, pass the same document and resources to
`VenueLayoutViewer`. Use `VenueLayoutPicker` with `onSelectionRequested` for
customer selection, or [mount the JavaScript picker](web/README.md) in a web app.
The original `VenueSeat*` grid API remains available for grid-based integrations.

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

## Integrate with your app

The package owns layout geometry, rendering, editing history and selection UI.
Your application owns pricing, live availability, authorization, reservation
locking, orders and payments. Failed or rejected async selection requests roll
back the optimistic UI; a visual selection does not create a reservation.

Licensed local font fixtures are included for examples. Hosts can supply their
own font/image resources without runtime font downloads.

| Task | Guide |
| --- | --- |
| Run the complete object editor and previews | [Example studio](example/README.md) |
| Embed the JavaScript viewer/picker | [Web integration](web/README.md) |
| Connect availability and reservations | [Backend integration](doc/backend-integration.md) |
| Persist drafts and understand JSON | [Editing and serialization](doc/editing-and-serialization.md) |
| Customize appearance | [Theming](doc/theming.md) |
| Maintain a grid-based integration | [Getting started](doc/getting-started.md) |
| Work with the shared layout model | [Core contract](doc/blueprint-v2/CONTRACT.md) and [operations](doc/blueprint-v2/CORE-API.md) |

[Hosted interactive demo](https://festappnet.github.io/venue_seat_picker/) ·
[Issues](https://github.com/festappnet/venue_seat_picker/issues) ·
[Contributing](CONTRIBUTING.md) · [Security](SECURITY.md)

Licensed under the MIT License.
