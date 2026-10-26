# Ticket layout editor

The editor paints the bitmap background, logo, QR modules and all text locally
in Flutter. Drag, resize, font changes, zoom, undo, cancel and Apply do not
request or render PDF. `preview-ticket-layout` resolve with `resourceProtocol: 3`
supplies only the authorized template, synthetic scenarios, product catalog,
font identities and active image references. It never loads gallery resources,
parses fonts, shapes text or generates PDF. Flutter creates the synthetic QR
locally with correction level M. Unsupported resource protocols fail explicitly;
new clients never retry the legacy binary resolve.

`automation/tickets/generate-preview-assets.ts` generates the shared
`ticket-assets/preview-manifest.json` from the PDF presets, exact font bytes and
retained artwork versions. Run it with `--check` to verify drift; CI and the web
build enforce this check. Flutter bundles the same assets for web and native.
The gallery starts loading only when opened, and loads visible editor cards.
`TicketPreviewAssets` verifies digests and owns a public image LRU capped at
24 MiB and 16 images; each session owns disposable clones. Settings and editor
reuse one authorized context. In-flight resolves deduplicate per context,
identity, scope and revision; metadata is never an authorization grant.

Private fonts are authorized on each missing-resource request and are absent
from the global public registration cache. Identity/capability changes discard
session references and late results. Private images use the existing image
Worker with the user's JWT, no redirects and no public URL conversion.

`ticketGeneration.ts` resolves saved layout data and resources; `drawLayoutTicket`
(in `generateTicket.ts`) is the sole PDF renderer. Download, email and PDF preview
all use it. The separate named and image-relative PDF implementations are removed.
Historical geometry import exists only in the offline converter. The runtime
accepts schema 3 and creates neutral presets for new, unconfigured slots. It
rejects legacy artwork configurations awaiting materialization. Saved layouts
and ordered product snapshots remain authoritative.

Bundled fonts (`futura`, `robotoSlab`, `roboto`, `russoOne`) are selected once per
ticket. The generated manifest supplies their exact bytes and metrics to Flutter and PDF.
Build generation performs the PDF embedding probe. Other registered fonts use
the existing private R2 namespace: a trusted first import publishes immutable
bytes followed by a versioned, digest-checked metrics sidecar. Ordinary reads,
including after worker restart, reuse this prepared resource without parsing
or PDF probing. Corrupt resources fail closed. `font` and explicit `layout-text`
retain their authorization; the old binary resolve survives only as an external
compatibility boundary for released clients.
Templates can store `flow` element IDs and `flowStep` to compact missing detail rows;
all ordinary presets retain fixed positions. QR contrast compares both colors.

## Shared font catalog

`supabase/functions/_shared/ticket-assets/font-catalog.json` is the sole pinned
catalog. Edge functions import it directly; Flutter bundles the same file through
`pubspec.yaml` and loads it through `TicketFontCatalog`. The generator
`automation/generate_ticket_font_catalog.mjs` produces that catalog, Dart legacy
font IDs and the append-only SQL seed from the locked font package. Do not add
another frontend copy. Existing font IDs, metadata and font bytes are unchanged.

## Contract

The optional `ticket.layout` contains `schemaVersion: 3` and `templates.wide`
and/or `templates.named`. Each template stores PDF points with a top-left
origin, a PDF page, a ticket area
and a flat list of elements. Each element has an id, binding, box, visible,
locked and style (fontSize, minFontSize, maxLines, color, align).

Bindings: qr, ticketSymbol, spotGroup, productType, note, price, occasionTitle,
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

Release the dedicated product cutover SQL/data transaction, all shared Edge
consumers and the selected tenant client in one fenced window. The exact
production ordering and unapplied gates are in the implementation evidence.
Do not apply unrelated pending migrations or deploy other tenant branches.


## Style choices and alignment

The generated local catalog includes classic, compact and event-title layouts, plus a portrait
layout with a ticket-sized PDF. The portrait choice clears the bitmap. The gallery renders
local thumbnails with the same font, event data and images as the canvas.
Selecting one copies geometry into the draft and is a single undo step; no PDF
request or saved style identifier is involved. Historical event image references
are distinct from geometry and must be reviewed before becoming reusable assets.

Known event title/date/place override synthetic values in all preview scenarios.
After authorization, preview reads one occasion catalog snapshot. Product fields
select an explicit `productTypeId` and editable label; data, warnings and flow
are addressed by element ID. Examples use the first visible product by order
and ID, with trimmed short/full titles selected by the shared server formatter.
The picker includes groups referenced by a form in this occasion, including
hidden fields. Already saved historical references remain printable, and hidden
purchased products are included in production rendering. No matching product
means no text or prefix. Catalog failures are visible and retry loads only the
catalog. Edits and undo project examples locally, without resolve/PDF calls.
Preview price deduplicates selected examples and never combines currencies.
Admission is identified by blueprint product membership, independent of the
product type classification. Names and table numbers
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


Production previews use real normalized catalog examples for explicit group IDs.
Names, table numbers and codes are synthetic. QR payloads use the preview
namespace and cannot match a real admission code. Historical PDF fixtures remain
unchanged as visual baselines; no customer credential is copied.

## Product type cutover operation

Active SQL, Dart and Edge contracts accept schema 3 only. Legacy schemas and
implicit artwork geometry are read only by the offline converter in
`automation/tickets/product-type-cutover/`. It preserves historical product
links and fonts, materializes both slots, removes unused print fields without
moving retained content, and never creates a transport field automatically.
The former runtime template importer and fixed dinner selector are retired.

Use `inventory.sql` with an explicit organization and current versions/hashes,
then `run.ts inventory|dry-run|apply|verify`. `apply` produces reviewable SQL
containing only the scoped forward migration, data conversion, sync invalidation,
audit and migration ledger in one transaction. It does not execute database
writes. Failed hashes abort the whole transaction; replay does not increment
versions. See [implementation evidence and production gates](../../../docs/plans/ticket-product-type-cutover-implementation-2026-10-13.md).
Production writes, deployment, commit and push require separate authorization.
A schema-3 occasion copy remaps both slots through the complete product type map
and validates them inside the existing atomic copy command. Direct catalog
reparent/delete writes are revoked. A purchased product cannot change group.

## Background upload quality

Backgrounds use the same `DbImages.uploadImage` → image Worker pipeline as all
other app images. The client selects `ticket-background` and sends original
bytes; the server owns the 1600 px edge, JPEG quality 90 and 2 MiB output
budget. PNG remains lossless with transparency, EXIF orientation is applied by
Cloudflare Images, and GIF/WebP print backgrounds become a still PNG. The editor
loads and compares the processed artwork before changing its current preview.
No browser JPEG/PNG encoder or separate ticket compression policy remains.

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


## Canvas color and panel organization

The properties panel groups canvas/paper, typography and artwork. Selected
object properties stay at the top, and a compact thumbnail leaves room for tools.
`canvasColor` is optional six-digit RGB or `transparent`; absent preserves the
historical gray fill. Transparency is shown as an editor-only checkerboard and
omits the canvas fill in PDF (paper margins and QR quiet zones stay white).
Color changes are undoable and cancel without changes. Escape/outside dismiss
nested dialogs; the editor protects unsaved changes with its discard prompt.
Deploy `20261003170000_ticket_canvas_color.sql` and the updated function bundle
before publishing the client.

Explicit canvas/element geometry edits materialize the currently displayed flow
positions once and remove compact-flow rules in that same undo transaction.
This makes bounds, dragging, resizing and magnets agree with what is painted,
including price rows shifted up past missing or hidden product/note rows. Canvas
magnets also include the cropped artwork; Alt and disabled snapping bypass them.

All editor color dialogs preview immediately, commit as one undo step, and
restore the original document on Cancel/Escape/outside dismissal. They share
used/artwork/basic swatches. Canvas transparency uses one 0-100% slider and
optional `canvasOpacity` (0-1, default 1); legacy `canvasColor: transparent`
remains fully transparent. QR contrast still gates Apply. Deploy
`20261003180000_ticket_canvas_opacity.sql` and the function bundle before client.

Canvas resizing supports all four edges and corners. Left/top changes rebase
element and artwork coordinates without scaling or moving visible content;
required QR/code bounds still limit shrinking. Attempting to move an element
in this mode pulses Done and explains how to return to element editing.

Canvas gestures discard pointer overshoot at hard bounds while retaining small
movements needed to escape magnetic snapping. Automatically hidden elements
keep their original geometry in editor-only recovery data tied to immutable
documents, so enlarging the canvas restores them across drags and undo/redo.
Manually hidden or subsequently edited elements are not automatically restored.
Recovery data is not serialized; reopening a saved layout uses its saved state.

Ticket dimensions and PDF format are edited in the persistent canvas settings
panel beside the full-page preview (below it on phones). Numeric dimensions
commit on Enter/blur through the same canvas controller as edge drags. Required
element blockers link directly to element editing. Changes use ordinary undo;
there is no second modal Apply step.

## Selection scaling

Shift/Ctrl/Cmd-click toggles selection; Shift-drag on empty space adds a marquee
selection. A multi-selection exposes eight shared resize handles. Resizing scales
unlocked boxes, their relative positions and text sizes around the opposite
anchor in one undo step. QR remains square and at least 60 pt; font size and
canvas bounds constrain the entire group uniformly.


## Adding optional elements

“Add element” offers event title, start time and venue separately,
table, order name, note, price and logo only when data exists and the field is
absent (including hidden fields). Product groups exclude already used groups and
groups without a sample. Repeatable free text replaces the footer choice; existing
footers remain editable as free text. New text inherits the most common body text
style, using the median font size to break ties, and uses unoccupied space.
Each insertion is one undo step. Ctrl/Cmd-Z and redo share document history across
the canvas and property inputs, including mobile panels. Nested dialogs retain
their own history until their change is accepted. Double-clicking an unlocked free
text (or legacy footer) edits it directly on the canvas, synchronized with the
properties panel. Escape finishes inline editing. Delete/Backspace outside text
inputs removes selected unlocked optional elements as one undoable change; QR
and ticket code remain protected. Source drafts allow ordinary fields while product editing stays unavailable.
Catalog retry appears only after a catalog load failure. Editor Cancel uses Storno
in Czech, consistent with the shared dialog wording.

`occasionStartTime` uses the occasion's `data.timezone`, defaulting to
Europe/Prague, and `occasionPlace` uses `data.place_name`. Both share the preview
and PDF normalization. Apply `20261016210000_ticket_optional_event_elements.sql`,
then deploy the shared Edge consumers before publishing the client. This additive
schema-3 extension does not change existing templates or their combined date/place.
Free text additionally requires `20261016220000_ticket_free_text.sql` and the
shared Edge renderer before client deployment. Its `text` binding carries at most
2000 Unicode characters; legacy footer bindings continue to render unchanged.

## Event design gallery

`ticketGallery.ts` owns the concert, ball, festival, club, theatre, exhibition,
gala, conference, cinema, sports, credential and workshop presets. Each has its own physical format and composition;
their geometry is authored in millimetres and converted into PDF points. All
twelve use ticket-sized pages, independently of the legacy storage slot.
Their immutable `https://img.festapp.net/ticket-presets/v1/` identities resolve
from bundled bytes in `ticket-assets/backgrounds`, including when a saved ticket
is rendered for email or download. No upload or external image host is needed.
`preview-manifest.json` maps each entry to its local source bytes and digest;
the selected source is saved through the ordinary background field. The two
curated Google Fonts are bundled with licenses and verified against the canonical
font catalog hashes. Regenerate procedural gradients with
`node automation/tickets/generate-backgrounds.mjs`; publish changed artwork under
a new versioned filename so existing tickets retain their appearance.

On macOS, generate the self-contained gallery and real PDF samples with
`deno run --frozen --lock=supabase/functions/deno.lock --allow-read --allow-write --allow-env --allow-run=sips automation/tickets/preview-gallery.ts /absolute/output/directory`.
The gallery opens directly from disk and includes source references and QR
palettes. Each design pairs its QR ink with an opaque, contrasting backing and
a four-module quiet zone; the existing validators own print constraints. Its graphic
perforation marks do not request physical finishing from a printer.


The local resource cutover and remaining release gates are recorded in
[`ticket-preview-local-resources-RESULT-2026-10-22.md`](../../../docs/plans/ticket-preview-local-resources-RESULT-2026-10-22.md).
The higher preview CPU budget remains intentionally enabled by the user's
2026-10-22 instruction. The email worker budget and recursive runtime assets
remain unchanged.

### Action palette for gallery artwork

New template selections use the draft's concrete `appearance.primary`,
`appearance.secondary` and `appearance.gradient` values. Presets only populate
these values; they never select a precolored image. Both preset and custom
palettes produce the same bounded `palette-<primary>-<secondary>-<template>-v2.png`
builtin resource ID. Solid styles supply the primary color for both inks.
`TicketPreviewAssets` renders it locally and `galleryBackground` renders the
same original artwork for PDF output; pixel parity is tested. Selection and
subsequent palette edits persist that resource ID as the ticket background.
Silk photographs retain their authored colors, and text/QR retain the neutral
contrast rules. Previously published `theme-*` images remain immutable readers
for already saved layouts; no new selection or generator emits those variants.

Artwork color ownership is defined by `ticketArtworkRoles` in
`ticketThemePalette.js` and generated into the client preview manifest. Each
composition identifies its primary surfaces and secondary accents using source
color anchors. The renderer applies the action's two inks to those roles while
retaining luminance for text contrast. It no longer guesses ink ownership from
whether a source pixel looks warm. Existing palette-v1 resource IDs retain their
original renderer for saved-layout compatibility; new choices emit v2 only.

## Email delivery

The event's `ticket.delivery_mode` selects `pdf_attachment` (the default when
absent), `inline_qr`, or `both`. SQL rejects other explicit values. Delivery is
independent of `ticket_type` and the print layout; changing it never resends
existing tickets. Disabled ticket features issue neither PDFs nor inline QR.
Inline delivery uses the existing ticket symbol in a PNG, with no PDF font,
background or layout dependency. PDF download and printing retain their current
renderer. Both representations share the admission state.

The settings screen and event setup Communication step edit the same feature.
Inline mode retains an optional PDF design for printing. Authorized server
previews use invalid sample codes, show attachment names, and never enqueue mail.
