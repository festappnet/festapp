# Ticket layout editor

The editor paints the bitmap background, logo, QR modules and all text locally
in Flutter. Drag, resize, font changes, zoom, undo, cancel and Apply do not
request or render PDF. `preview-ticket-layout` in `resolve` mode supplies the
server-owned preset, synthetic scenarios, font bytes/advance metrics and QR
matrix. Images are decoded once when their source changes.

`ticketGeneration.ts` resolves saved layout data and resources; `drawLayoutTicket`
(in `generateTicket.ts`) is the sole PDF renderer. Download, email and PDF preview
all use it. The separate named and image-relative PDF implementations are removed.
`ticketTemplateImport.ts` is a one-way data adapter for existing feature records
without a layout. It imports geometry, bundled original font, QR foreground and
background/opacity/quiet margin, named border, and compact optional rows. It never
renders PDFs. Saved edits take precedence. The adapter remains for unmigrated
organizations and may be removed once their configured ticket features all store
layouts; blank events use the ordinary preset. Unknown historical font URLs fail
explicitly rather than silently substituting a font.

Bundled fonts (`futura`, `robotoSlab`, `roboto`, `russoOne`) are selected once per
ticket. The server supplies the same font bytes and metrics to Flutter and PDF.
Templates can store `flow` bindings and `flowStep` to compact missing detail rows;
all ordinary presets retain fixed positions. QR contrast compares both colors.

## Contract

The optional `ticket.layout` contains `schemaVersion: 1` and `templates.wide`
and/or `templates.named`. Each template stores PDF points with a top-left
origin, a PDF page, a ticket area
and a flat list of elements. Each element has an id, binding, box, visible,
locked and style (fontSize, minFontSize, maxLines, color, align).

Bindings: qr, ticketSymbol, spotGroup, food, note, price, occasionTitle,
occasionDatePlace, orderName, logo, footer. Missing values leave fixed boxes
empty unless their template explicitly enables compact flow; zero prices remain visible. Multiple products select the first matching
product by order-product-ticket id. OrderName means the order's name/surname,
not an independently verified ticket holder. Hidden notes never enter print
content. Background references remain in the existing ticket feature, so the
occasion media copier can replace the URL without rewriting geometry.

Text uses the repository Futura PT Book bytes in both runtimes, explicit glyph
advances, wrapping including long words, half-point shrink steps, then ellipsis
with a warning. Unsupported glyphs are replaced with `?` in both outputs. Ticket
symbols may never truncate. QR is square, at least 60 pt, printed as vector
modules, with an opaque white four-module quiet zone. Its editor palette only
contains dark high-contrast colors. Text must not overlap its protected box.

## Persistence and lifecycle

The production editor Save action persists only ticket layout, artwork and type
through the existing versioned occasion command. It loads the saved occasion,
checks the settings version and preserves unrelated unsaved form edits. Failures
keep the editor open; successful saves advance the parent version and layout
baseline. Local fixture previews still return a draft. The occasion save transport
adds `ticket_layout_change: {expected, next}` only if layout changed. This
command envelope is never persisted in the occasion JSON. SQL locks the row,
preserves layout when the command is absent, validates explicit changes and
rejects stale expected values before writing. Command versioning and receipt
replay remain in force. Direct authenticated feature writes are revoked without
broadening existing table/column access. Unknown layout schemas are preserved
and cannot be edited or downgraded.

On conflict the user can load the stored layout while retaining a local copy,
and restore that copy explicitly. Upload failure restores the previous bitmap;
Cancel never deletes stored or newly uploaded objects. Unreferenced uploads are
left to the existing image cleanup. A changed aspect ratio offers keep positions
or restore preset. Only one PDF request can be active; its result is ignored if
the document, scenario or image changed before completion.

## Verification and deployment

Shared fixtures: `test/fixtures/ticket_layout/layouts.json` (Dart/TS/SQL) and
`resolve.json`; reference historical PDFs use local image/font resources.
SQL fixtures are embedded for the SQL-only runner and checked against the JSON
by the Deno suite. Flutter tests cover controller gestures, live repaint before
pointer up, zero implicit PDF calls and draft serialization. Deno tests cover
schema, dispatch, normalized content, vector QR and preview authorization.

Deploy separately, in order: `20261001120000_ticket_layout_editor.sql`, the
updated `download-ticket`, `send-tickets` and new `preview-ticket-layout` plus
shared sources/font asset, then the Flutter client for the selected tenant.
The runtime policy and coverage matrix include preview. No tenant rollout is
implied. Once a layout is saved, backend rollback must keep supporting it.


## Style choices and alignment

Resolve includes classic, compact and event-title layouts, plus a portrait
layout with a ticket-sized PDF. The portrait choice clears the bitmap. The gallery renders
local thumbnails with the same font, event data and images as the canvas.
Selecting one copies geometry into the draft and is a single undo step; no PDF
request or saved style identifier is involved. Historical event image references
are distinct from geometry and must be reviewed before becoming reusable assets.

Known event title/date/place override synthetic values in all preview scenarios.
After authorization, preview reads the occasion's product catalog and selects
the first visible admission product (by id) and a dinner in the same currency.
The displayed price is their sum and dinner uses its short title when present.
An empty or unusable catalog uses the illustrative dinner and price fallback;
a real catalog without dinner leaves that field empty. Names and table numbers
remain illustrative. The QR stays deliberately invalid.
Resolve reads these fields from the authorized occasion on the canonical backend.
Without an assigned background, custom layouts use the same plain fill in
the editor and PDF; a failing explicitly assigned image still fails visibly.

Grid (10 PDF points) and snapping are separate session controls. Snapping aligns
edges and centers with the ticket/other elements, additionally using grid targets
when visible. Pink guides explain the match. Alt temporarily disables snapping.
The pointer's unsnapped drag position is retained, so slow movements can leave a
magnet. Grid and guides do not enter the saved layout or printed PDF.

Pan and zoom keep the ticket within the viewport when it fits; when zoomed in,
pan stops at its edges instead of allowing it to disappear. Scale calculations
use the two canvas axes, excluding the Matrix4 z-axis. Double-clicking font-size
or line-count sliders restores that property's selected-template default as an
undoable edit. Locked elements remain unchanged.

## Local historical-reference gallery

`test/components/ticket_layout/editor_preview.dart` opens the full wide editor
immediately. Its existing template picker contains three original landscape
backgrounds (cream, forest green and black and white) plus a plain portrait, with source metadata in
`test/fixtures/ticket_layout/historical/`. Each thumbnail paints its own artwork
and matching layout. Selecting a template changes artwork, geometry and colors
without leaving the editor. Artwork selection participates in geometry undo/redo;
Apply preserves the selected artwork when the local editor is reopened.
The optional decoded artwork catalog is owned/disposed by editor resources.
The named example still uses its existing geometry presets. This local catalog
does not publish assets or change production event data.

## Ticket dimensions, colors and PDF preview

The editable canvas is `ticketArea`. Existing sheet layouts keep their page;
`pageFit: "ticket"` makes the page exactly match a zero-origin ticket area.
New named/portrait presets use this explicit mode (initially 200 x 375 pt).
Both dimensions must remain within 60-842 pt, validated in Dart, TS and SQL.
The optional field preserves existing saved fixed-page layouts. The dedicated
`20261002001000_ticket_sized_pdf_pages.sql` migration adds the SQL validation.
Portrait resizing changes page and area together; wide backgrounds remain on A4. The dimensions dialog uses millimeters; resizing fits element positions
and uniformly scales their boxes/fonts, preserves square QR codes, and rejects
sizes that cannot satisfy the print/QR contract. Resizing is one undo step.
Image-backed initial layouts fit the image ratio into the sheet where printable;
extreme ratios retain minimum space for QR/text. The dimensions dialog can
restore the image ratio at the current width. Images use contain, never stretch.

Color properties open the same `flutter_colorpicker` saturation/hue control as
map paths. Text supports a precise hex value; QR uses visual swatches from the
existing print-safe palette. Apply creates one undo step; Cancel changes nothing.

The PDF action calls `preview-ticket-layout`, displays returned bytes in an
embedded browser PDF viewer, and offers Download PDF. Other platforms retain
the download action. Font overflow warnings are shown in the preview. A document
changed during a request cannot display stale PDF output.

The local preview uses `preview_server.ts` on loopback port 8769 to serve its
Flutter build and call the actual Edge handler with fixture-only dependencies.
Its sample data comes from resolve, so the canvas and PDF use identical fields.
The local image upload is bounded and kept in memory; it never uploads to a live
tenant. Production authorization and image-origin checks remain in the handler.

Start the local runtime after preparing the web build and fixtures:

```sh
SUPABASE_URL=http://127.0.0.1:1 SUPABASE_SERVICE_ROLE_KEY=local-fixture \
  deno run --allow-env --allow-read --allow-net=127.0.0.1:8769 \
  test/components/ticket_layout/preview_server.ts /tmp/festapp-ticket-editor-web
```

Only one server may own port 8769. This replaces the old static Python server;
that server cannot handle PDF POST requests. No production deployment is implied.

The dimensions dialog preserves exact geometry when displayed rounded values
are unchanged. Restore template dimensions and use image aspect ratio are
separate actions. Fresh tickets without a saved layout/background open the
internal template picker first. The scenario selector uses a compact menu
rather than a filled form field. Production rollout must apply the page-fit
validation migration and updated renderer before publishing the new client.


## Phone layout

Below 900 logical pixels the editor keeps a single compact toolbar and the full
remaining canvas. Grid, snapping, pan/zoom and sample scenarios are in the tools
menu. Elements and properties open a dismissible bottom sheet with two tabs;
selecting an element takes the user directly to its properties. The template
picker uses one column on phones. Color/dimension dialogs remain scrollable with
the keyboard visible. Browsers without an embedded PDF viewer get an explicit
Open PDF action, with the existing download action always available.

QR geometry is quantized to 1/1024 pt when moved/resized. Binary-exact coordinates
preserve its square shape across Dart Rect arithmetic and JSON validation at
phone zoom levels; this is below printable pixel precision.


Preview fields follow inspected Skautský ples 2026 purchases: ten-character
code shape (X382 prefix), 200 CZK admission plus a 170 CZK dinner, and the actual
short dinner title. Customer names/codes are not copied. The printed sample
code looks like a normal ticket; the QR payload has a preview namespace and
cannot match a real admission code. Preview artwork has no printed watermark.

## Existing-layout import operation

`automation/tickets/import-layouts.ts inventory.json plan.sql ORGANIZATION`
creates a reviewable forward-only transaction from an explicit tenant inventory
(`id`, `organization`, `features`, `data.font`, `features_hash=md5(features::text)`).
It only imports configured artwork/named tickets without saved layouts. Missing
assets are reported separately and never substituted. Run reviewed SQL through
`access-sql.py`; every write checks the full feature hash and original font,
protects concurrent edits, validates the layout and is safe to repeat. Unconfigured
events still get the first-open gallery. The save RPC rejects older clients that
would discard the migrated font/appearance contract; reload the deployed editor.

## Background upload quality

`TicketBackgroundImage` owns the print-artwork preparation policy: 1080 px on
the longer edge, JPEG quality 85, and an 800 KiB output budget below the existing
10 MiB upload/PDF limit. Suitable PNG/JPEG inputs are kept byte-for-byte; PNG
transparency is preserved. Oversized images scale down without upscaling or a
second JPEG pass. The upload service passes the same limits to the Worker so its
ordinary 1200 px / quality 70 defaults do not recompress prepared ticket artwork.
EXIF orientation is baked when necessary, and other decoded formats become PNG
for the shared PDF renderer. Native platforms prepare in a compute isolate.

QR colors are edited together in the shared color picker: foreground/background
selection, HEX entry, paired preview and a swap action. Contrast gates Apply,
not individual color changes, so inversion is possible in one undoable edit.
A changed background becomes opaque; otherwise imported opacity/quiet margins
remain intact. These values persist through the existing layout contract and
are consumed by both the canvas and the sole PDF renderer.

## Paper and image placement

The dimensions dialog separates ticket dimensions from the PDF paper: A4 or
ticket size plus an adjustable uniform white paper margin (0-25.4 mm).
Gallery templates and switches to ticket-sized paper start with 3 mm. Opening
the dimensions dialog proposes 3 mm for old layouts without a saved margin;
cancel preserves the draft. Explicitly saved margins, including zero, are retained. Ticket dimensions scale the design independently of paper. New ordinary templates default to A4; explicitly portrait
gallery styles retain ticket-sized paper. Existing saved paper sizes are kept
until changed. Switching paper preserves element and image geometry.

“Position image” enters a canvas mode that moves only the artwork. Dragging
(or arrow keys) changes its position; four corner handles change its scale while
preserving aspect ratio and the opposite corner. Image, text and QR transforms
share the same snapping policy for ticket edges, centers, elements and visible
grid. Alt temporarily disables magnets. The full image outline remains visible
outside the crop while editing. Fit
whole image, Fill ticket and Center provide starting positions. Smaller artwork
leaves room for text; larger artwork is clipped to the ticket in Flutter and PDF.
The optional `backgroundTransform` stores a scale (0.1-10) and x/y offsets in
units of ticket width/height (-10 to 10); absent values preserve centered contain.
Each gesture is one undo step. Paper previews cancel without changing the draft.
Editor controls follow the app brightness; printed colors remain unchanged.

Deploy `20261003120000_ticket_background_transform.sql` and the shared PDF
renderer in download-ticket, send-tickets and preview-ticket-layout before the
client. The migration only extends validation and does not rewrite saved layouts.

`pageMargin` is optional in points (0-72), valid only with `pageFit: ticket`.
The ticket origin equals the margin and the PDF page adds twice the margin on
each axis. Deploy `20261003154500_ticket_pdf_margins.sql` and the shared function
bundle before the client; existing saved templates need no rewriting.

The image crop mode uses four free-aspect corner handles and a draggable crop
rectangle. It shares the canvas magnets and supports undo and reset without
modifying or re-uploading the source image. Optional `backgroundCrop` records
normalized x/y/width/height within the original artwork; absent means the full
image. Flutter and PDF intersect this crop with the ticket area while retaining
the original image transform and element geometry. Deploy
`20261003163000_ticket_background_crop.sql` and the function bundle before the client.

Crop editing uses L-shaped corner marks. The faded original is visible only
while editing the crop. Placement, resizing, snapping and the sidebar thumbnail
use the visible crop bounds, with the original full-image transform retained
for PDF rendering and restoring the crop.

Ticket canvas resizing uses a dedicated mode with right, bottom and corner
handles, live millimeter dimensions, shared magnets and one undo step per drag.
Canvas handles and numeric dimensions change the surface without scaling or
moving artwork, QR or text. Optional elements extending outside become hidden;
their hidden boxes are bounded to satisfy the existing storage contract. Undo
restores original visibility and geometry. Within a gesture, expanding restores
content from its original snapshot. Required QR/code bounds clamp the canvas and
are highlighted orange with their names. Hidden optional elements never block
shrinking. Numeric edits preview valid sizes and name required blockers on Apply.
Ticket-code edits automatically enlarge undersized boxes using the actual font
metrics, staying inside the canvas and clear of QR. The same repair runs when
opening old drafts and before saving, avoiding the generic too-small-box error.
