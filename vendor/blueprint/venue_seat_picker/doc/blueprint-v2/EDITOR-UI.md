# Shared editor UI

The canonical Flutter library is `package:venue_seat_picker/editor_ui.dart`.
Its implementation lives in `lib/src/editor_ui/` and imports no venue, Ticket,
backend, reservation or font-catalog models. Both editor hosts call these same
widgets. This is a Dart sublibrary, so a separate unpublished package is not
needed.

The shared UI owns the color/opacity dialog, swatches, artwork suggestions and
font selection/search/loading/error interaction. Hosts own font catalogs and
resource loading, persisted values, validation, preview/cancel, and undo/redo.
Ticket QR contrast rules remain in the Ticket adapter. Font IDs are never
replaced by their display names. Cancel never commits a draft color.

The color value is RGB hex plus a separate finite opacity in 0-1. Conversion to
venue RGBA hex happens only in the venue adapter. Ticket canvas opacity retains
its existing double precision. Generic color dialogs can edit one color or a
foreground/background pair, accept a host validator, and emit live previews.

The font picker accepts metadata options with separate stable IDs and family
names and awaits the host selection callback. It never downloads a font or
introduces another catalog. Failed loads keep the previous selection visible.

Removal set: the venue's private color dialog/font dropdown and the Ticket
editors' independent color-dialog implementations. The existing Festapp
`FontFamilyPicker` may remain only as a mechanical localization/catalog adapter
because Forms also consume its interface. No duplicate picker UI remains there.

This request authorizes shared UI extraction and its Ticket consumers. It does
not authorize blueprint data integration, SQL changes, publication or deployment.
The Festapp development checkout resolves the local package through a documented
`pubspec_overrides.yaml`; the production git pin is unchanged until a separate
package release is authorized. This override is local dependency resolution,
not a runtime compatibility implementation.

## Desktop and shared UI checks - 2026-10-18

The desktop demo includes a permanent left object palette with previews, default
translation/rotation snapping, a Czech host shell, and an explicit 72-seat sample
hall action which protects an existing draft. Fresh templates no longer draw
duplicate stage/dance-floor captions. Existing saved documents are preserved.

The root Flutter suite passed 56 tests with one opt-in raster test skipped
(`build/qa/shared-editor-root-tests.log`). After the final font dialog scrolling
and color localization fixes, the shared UI and editor widget suites and targeted
analyzer passed again (`shared-editor-final-tests.log` and
`shared-editor-final-analyze.log` in the same directory).

Twelve targeted Festapp consumer checks passed through the collected default and
Czech session roots: font selection/search/failure/reset/loading/compact layout,
artwork palette delegation, text color transactions, paired QR contrast and
atomic history, exact canvas opacity, transparency, Escape and preview cancel.
The compact font dialog regression required scrolling its title and content;
the final failed-case recheck passed. Consumer analysis has no errors or warnings
and retains three pre-existing style infos. These are local adapter checks, not
a production release or complete Festapp application E2E.

For local Festapp resolution, `pubspec_overrides.yaml` repeats the existing map
overrides as well as the two venue paths because Pub replaces the entire
override map. Keep the production git pin unchanged. Updating that pin requires
a separately authorized package publication.

Reproduce from the respective repository roots:

```sh
# venue_seat_picker
fvm flutter test --reporter compact
fvm flutter test test/editor_ui_test.dart test/layout_editor_widgets_test.dart --reporter compact
tool/demo.sh build

# festapp, with the local overrides above
fvm flutter test --no-pub test/sessions/shared_default_1_test.dart --name 'font_family_picker|color wheel|preserves exact solid|selects a meaningful accent' --reporter expanded
fvm flutter test --no-pub test/sessions/shared_czech_test.dart --name 'text color picker applies|QR foreground and background edit|shared canvas color retains|canvas color dialog cancels|canvas colors preview immediately' --reporter expanded
```
