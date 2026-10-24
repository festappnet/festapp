# Ticket layout boundaries

The Flutter canvas and generated PDF share a saved geometry and resource
contract. Changing either renderer requires checking the other and SQL validation.

## Owners

| Boundary | Source |
|---|---|
| Saved schema, geometry and Dart validation | `models/ticket_layout.dart` |
| Gestures, selections, resizing and undo | `ticket_layout_controller.dart` |
| Resolve/PDF requests, fonts and decoded artwork | `ticket_layout_service.dart` |
| Save against the current occasion version | `ticket_layout_saver.dart` |
| TypeScript schema and validation | `supabase/functions/_shared/ticketLayout.ts` |
| Resource loading and print data normalization | `supabase/functions/_shared/ticketGeneration.ts`, `ticketRenderData.ts` |
| PDF drawing for download, email and preview | `supabase/functions/_shared/generateTicket.ts` |

Repository-root paths are used for backend files. Keep numeric limits and the
complete binding list in the executable validators instead of another table here.

## Saved data and print resources

Runtime layouts use `schemaVersion: 3` with `wide` and/or `named` templates.
Coordinates are PDF points with a top-left origin. Paper size, `ticketArea`,
background transform/crop and element boxes have separate meanings; a paper
change must not silently rescale the artwork or text. Canvas resizing protects
required QR/code bounds. Editor-only recovery for automatically hidden optional
elements is not serialized.

Text bindings resolve through server-normalized order/product data. `orderName`
means the order's name/surname, not an independently verified ticket holder.
Hidden notes must not enter print content. Product labels/references resolve by
stable IDs, and historical purchased products remain printable. QR previews use
an invalid synthetic payload; never copy a customer's admission credential into
an editor fixture.

Templates select a registered `fontId`; individual text elements may override it.
The pinned catalog is
`supabase/functions/_shared/ticket-assets/font-catalog.json`. Flutter bundles
that same file through `TicketFontCatalog`; the backend resolves its registered
bytes and metrics. Legacy names map to immutable IDs. Do not add a second
frontend catalog or accept client-supplied font URLs. The generator also owns
Dart legacy IDs and the append-only SQL font seed.

Text wrapping, overflow handling, QR size/contrast and quiet-zone geometry must
agree across Dart, TypeScript and SQL. A ticket symbol cannot silently truncate.
Use the shared fixtures when changing those rules.

## Preview and save lifecycle

Ordinary edits, drag/resize, zoom and undo paint locally and make no PDF request.
`preview-ticket-layout` resolve supplies authorized presets, example data, font
metrics and QR modules. Decode artwork only when its source changes. PDF is an
explicit action through the shared renderer; ignore an in-flight result if the
layout, scenario or image changed before it completed.

`ticketGallery.ts` owns the concert, ball, festival, club, theatre, exhibition,
gala, conference, cinema, sports, credential and workshop presets. Each has its own physical format and composition;
their geometry is authored in millimetres and converted into PDF points. All
twelve use ticket-sized pages, independently of the legacy storage slot.
Their immutable `https://img.festapp.net/ticket-presets/v1/` identities resolve
from bundled bytes in `ticket-assets/backgrounds`, including when a saved ticket
is rendered for email or download. No upload or external image host is needed.
`presetArtwork` supplies each gallery entry's source and decoded preview bytes;
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

`TicketLayoutSaver` reloads the saved occasion, checks its aggregate version and
persists only the ticket layout, background and type through the existing
occasion command. Preserve unrelated form drafts. A changed layout carries
`ticket_layout_change: {expected, next}` in the command envelope; that envelope
is not stored in occasion JSON. SQL preserves a layout when the command is absent
and rejects stale explicit changes. Unknown schemas cannot be edited/downgraded.

On failure, retain the draft and keep the editor open. Conflict recovery can load
the stored layout while preserving a local copy for explicit restoration. Cancel
does not authorize deleting stored or newly uploaded image objects.

Each gesture is one undo step. Crop/position changes preserve source image bytes;
canvas and paper controls must keep their distinct geometry contracts. Phone
controls use the same controller, validators and save path as desktop.

## Fixtures and release boundaries

`test/fixtures/ticket_layout/layouts.json` and `resolve.json` exercise shared
Dart/TypeScript/SQL behavior. The
[historical artwork fixtures](../../../test/fixtures/ticket_layout/historical/README.md)
are local references with embedded old event text, not reusable production
artwork. The local editor/PDF harness is
`test/components/ticket_layout/preview_server.ts`; its fixture network boundary
does not establish production authorization or printer/device acceptance.

Schema extensions require compatible SQL and the shared Edge consumers before
the selected tenant client. Do not replay old per-feature migration commands
from a README. Verify the current schema and release the exact reviewed artifacts.

Legacy implicit layouts are materialized only by the
[offline product-type converter](../../../automation/tickets/product-type-cutover/README.md).
Keep that import graph out of runtime rendering; historical migration files and
already delivered PDFs remain unchanged.

Numeric paper/canvas fields reuse `EditorNumberScroll` from
`package:venue_seat_picker/editor_ui.dart`. Only a focused field under the
pointer consumes wheel input; standard field edits still pass through the
existing controller validation and gesture/undo boundary.

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

Pregenerated batch documents use this same renderer through an explicit frozen
resource/catalog adapter. They require a saved active template with no visible
`orderName`. One sealed manifest stores private font/artwork bytes and render
inputs; later changes to the saved layout cannot regenerate an issued batch.
Failed document preparation resumes the existing batch and immutable part keys.
