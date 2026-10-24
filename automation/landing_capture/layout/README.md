# Reproduce layout clips

Real package editor, localized through its own `VenueLayoutLocalizations`.
No translated overlay. This is the standalone editor example; public purchase
footage is separately captured from Festapp (see `../picker`).

Prerequisites: `fvm`, Python 3, Node, ffmpeg, installed `agent-browser` and
`product-demo-video` skill. `LAYOUT_PACKAGE` points to the sibling
`venue-seat-picker-public-preview-20261021` checkout (recorded source HEAD
`0b881853bd9071784fd66102a03a1606a81afa79`). Preserve its existing edits.

1. Set `CAPTURE_DIR` to a fresh directory outside Git; `CAPTURE_LOCALE=cs` for
   this delivery, `en` for a later English recording. Set `MEDIA_DIR` to an
   output directory. Optional `PRODUCT_DEMO_SKILL` overrides the installed skill.
2. Run `python3 prepare_host.py "$LAYOUT_PACKAGE"`. It writes a capture-only
   `example/lib/landing_capture.dart` without changing the normal entry point.
3. Check the workstation Flutter slot. In the example directory run
   `fvm flutter build web --release --target lib/landing_capture.dart --dart-define=DEMO_LANGUAGE=cs --base-href=/ --output="$CAPTURE_DIR/app"`.
   Use the chosen locale in the define. The explicit locale selects actual UI
   translations and translates the template's default labels before rendering.
4. Run `python3 prepare_resources.py "$LAYOUT_PACKAGE" "$FESTAPP_ROOT" "$CAPTURE_DIR" --document fixtures/vivid-document.cs.json`.
   This uses the canonical text shaper from the recorded Festapp main revision
   and the actual 160px palette factory with inherited template styles. The
   editor normalizes equal-sided ellipses to circles at insertion; the recipe
   preserves that actual saved shape. Pass `--locale en` for English labels.
   Then serve this real application on a task-owned loopback port. Create an empty
   JSON config and `$CAPTURE_DIR/ab` wrapper containing **every** command's
   `--config`, `--headed false`, unique `--namespace` and `--session` arguments.
   Verify the daemon's Chrome child is headless with a temporary profile and
   that the CDP page list has exactly one task-owned page. Never auto-connect.
5. After changing prepared resources, close and recreate the **task-owned**
   browser to obtain a fresh HTTP cache. Ordinary reload previously kept stale
   fixtures even though the actual document compiled with zero resource issues.
   Then open the application, set viewport 1440x960 and media light, enable Flutter
   accessibility with the actual `flt-semantics-placeholder` control. Do not
   change app state through injected application internals.
6. Run `python3 vivid.py --prepare` for the current vivid treatment. This uses
   genuine controls to remove the tiled floor, select Minimal style, color the
   left zone blue and the right zone amber, and copy navy chair styling.
   The recording adds a round table, adds chairs and Ctrl-drags a second table.
   The second clip changes a selected zone from blue to amber and reveals the
   finished plan. `capture.py` uses actual controls and native gestures.
   Cues and frame times use epoch seconds; keep every take and its journal.
7. Run `python3 finish_vivid.py`. Preserve native action timing, 30fps
   H264/yuv420p, CRF20, faststart. Desktop1200x760 and portrait720x900 are
   editorial crops of the genuine desktop editor, not a mobile editor claim.
   The hero crops only actual plan paper (892x716 at250,168) to860x690.
8. Full-decode each output with ffmpeg, compare duration against cues and view
   action + result frames. Keep final PNGs for hero and layout gallery.
9. Close only this browser and server. Keep raw frames/masters outside Git.

The earlier `shoot.py`/`finish.py` scripts retain the first iteration for
historical reproduction. Current delivery uses `vivid.py`/`finish_vivid.py`.
Keep `vivid-document.json` beside the raw takes. Style copy can change inherited
font properties: prepare canonical requests from that actual document, merge
resources, then recreate the owned browser before recording. Never crop away a
missing-resource banner as a substitute for fixing its cause.

For later YouTube assembly use the ordered clip manifest in the parent folder;
retain clean masters, do not concatenate already cropped mobile exports.

The capture-only host exports its genuine current document read-only as
`window.captureLayoutDocument`. Use it to diagnose resource requests; never
inject edits through that property. It does not render any artificial UI.

For a recorded document with copied appearance, pass `--document /absolute/path/to/document.json` to `prepare_resources.py` (repeatable). This calls the sibling's canonical `export_fixture_requests.dart` on that exact saved document, shapes its genuine requests, retains the previously served palette/locale corpus, and atomically replaces the served fixtures. Do not synthesize IDs or substitute a similar font. Revision 2 vivid document required two extra normal-face resources for Stůl 9/10 at size 16, lineHeight 1.2, language und, box 160x160; its larger template text requests were already present. The prepared exact document returned `compileScene(...)[issues] == []`. New fonts/sizes after further UI changes require exporting that resulting document again.

## Current delivery: authentic reference template

The latest user revision supersedes the vivid invented presentation with the
existing product template `scout-ball-182` (Skautský ples - původní sál).
Its unedited source has 182 seats and31tables and is traced from the original
reference hall, with the source digests in `scout_reference_data.dart`.
The real public Festapp picker uses that same unedited reference geometry.
The editor footage demonstrates adding two tables to a copy of this template;
it does not claim those unsaved edits were submitted into the public shop.

Prepare text resources using the same command above with
`--document fixtures/authentic-edited.cs.json --document fixtures/authentic-palette-request.cs.json`, then recreate the owned profile. The second document is a resource-request fixture for the fresh-session table label2; the actual final take document remains unchanged. Repeated rehearsals advance the editor naming counter.
Run `authentic.py` and `finish_authentic.py` instead of the historical scripts.
Two genuine native drags run from the left table palette to open areas alongside
the original left seating zone, followed by a separate chair drag from the left
palette beside the first new table (31→33 tables,182→195 seats). The inspector is excluded by a fixed editorial
crop, not hidden or replaced in the application. No form/style inspector enters
this capture. Final dimensions:1140x824 desktop,820x824 portrait-oriented crop.
The finished-plan shot includes the whole canvas. Native gesture cadence and
cue journals are retained without speed-up. Source frames remain external.

The second clip shows actual stock scout hall, Galaxy cinema and theatre templates. The conference cue is retained
only in the raw take and excluded from delivery because its stock labels overlap. It is explicitly a template overview, not a
claim of drawing those plans in one gesture. All their built-in labels are
localized by the real UI. New gallery stills use those exact rendered plans.
No hero image is generated in this revision. For English, rebuild the genuine
host with `DEMO_LANGUAGE=en`, set `CAPTURE_LOCALE=en`, generate translated
resource requests and rerun the same gestures; do not translate footage with
an overlay. Keep a new take directory for each language.

## Current delivery: empty hall growth and inherited typography

This revision supersedes the preceding editor takes. `growth.py` starts a
capture-only empty copy of the authentic scout architecture (`DEMO_EMPTY=true`,
`LAYOUT_TEMPLATE=scout-ball-182`). It removes the parket label through real
Alt-selection/Delete, then drags one table, Ctrl-drags fifteen actual copies,
adds table17 and clicks the actual seat-count plus twice (6→8), adds and resizes
a round table18, then clicks plus twice (6→8). Actual final counts:18tables,
112automaticchairs. The public picker separately retains the original stock
reference hall; no claim that the unsaved authoring exercise was published.

Build with the flags above plus `--dart-define=DEMO_EMPTY=true
--dart-define=LAYOUT_TEMPLATE=scout-ball-182`. Run
`prepare_growth_resources.py "$LAYOUT_PACKAGE" "$FESTAPP_ROOT" "$CAPTURE_DIR"`
before opening a fresh browser profile. It shapes the actual observed insertion
and resize geometries, generating labels1-20 through canonical request export.
The saved rehearsal documents are resource fixtures only, never injected UI.
For EN use `--locale en` and rebuild the actual host in English; inspect all
translated controls before recording. `pointer_gesture.mjs` derives from the
product-demo-video native gesture helper, adding genuine Alt modifier support.

Run `growth.py`, then `encode_growth.py TAKE_DIRECTORY --output-dir EXTERNAL_REVIEW_DIRECTORY` and copy its approved four MP4/JPG outputs into `MEDIA_DIR`. Run `encode_style_growth.py` with `CAPTURE_DIR` and `MEDIA_DIR` set. The build
edit speeds ONLY the repeated-copy cue8x; all other actions remain1x. Actual
seat-count controls are cropped from the same source frames and inset alongside
the table detail. No control or result is drawn synthetically. The style edit
shows global tablefill#80BDF2 and seatfill#253759, followed by actual cinema and
theatre templates. Desktop1140x824, mobile820x824; mobile preserves the whole
composition with plain padding. Rawcue timestamps and `growth-edit.json` retain
cuts for future YouTube assembly. The table-colour and seat-colour source cues
have a rehearsal gap between them; the edit excludes that gap explicitly.

Required sibling fix: common label typography lives in `styles.kinds.table.label`
in `scout_hall.dart` and `scout_balcony_hall.dart`, not each table override.
`venue_layout_controller.dart` infers numeric naming only when all existing
nonempty table labels are numeric, preserving explicit labels and collision
avoidance. Four new regression cases and four existing reference geometry cases
passed before the one capture build. Existing sibling dirty changes are retained.

## Latest delivery: actual Festapp brand and objects-only palette

Run `prepare_brand_host.py "$LAYOUT_PACKAGE" --locale cs` instead of the earlier
host preparation. It hosts the saved empty scout architecture with canonical
Futura PT Book family, regular400 labels, navy#253759 and tableblue#80BDF2.
Table/architecture outlines are3worldunits, seats have0stroke. At the recorded
canvas scale table outlines are approximately0.67physicalpixels before export.
This is real document styling and an actual Flutter FontLoader using the bundled
Futura bytes, not screenshot recoloring or substituted glyphpaths. No shared
product source changes are added in this revision.

Build the same target as above. Run `prepare_growth_resources.py PACKAGE
FESTAPP_ROOT CAPTURE_DIR --brand`, then `prepare_resources.py PACKAGE FESTAPP_ROOT
CAPTURE_DIR --brand-font --document fixtures/brand-cinema.cs.json --document
fixtures/brand-theatre.cs.json`. These use the canonical catalog's immutable
Futura family/face IDs and existing shaper. Fresh browser profile is mandatory
after changing resources. Run `CAPTURE_EMPTY_READY=1 python3 growth.py` build()
only, then `brand_templates.py` for actual stock Cinema198 and Theatre188.
Cinema gets its red seatfill through the genuine global controls; premium rows
retain their stock distinct rose appearance. Futura is selected through the
actual global font dropdown. No Galaxy template is delivered.

Use `encode_brand.py TAKE --output-dir OUT` (then copy approved outputs) and
`encode_brand_style.py`. Both object-grid crop and canvas crop come from the same
rawframe. Palette excludes search/templates/header; pluscontrol is omitted, but
actual chairgrowth remains visible. Copycue alone8x; all other gestures1x.
Clean gallery crops remove editor chrome. The first gallery item describes the
actual18table/112seat working copy, not the unmodified182seat public reference.

For EN use host`--locale en`, build`DEMO_LANGUAGE=en`, resource`--locale en`,
`CAPTURE_LOCALE=en`. The empty architecture translates its actual label data;
export the real English cinema/theatre documents and pass them to the same
resource preparer before the final English take. Keep sourceframes and cues for
future YouTube; no long film was requested or generated.

## Continuous native drag correction

Latest encode_brand.py uses one continuous1128x716 source rectangle at0,168,
translated to6,54 in1140x824. Previous separate palette/canvas crops removed
sourcecolumns232-338, where the genuine dragfeedback travels, causing apparent
disappearance. The new cut preserves original spatialrelationships through the
entire gesture. Only static palettechrome above sourcey360 and the partialbottom
objectrow are covered with exactmatte; nativeghost and pointer are never drawn or
reconstructed. Source JPEGfullrange is normalized tolimitedrange before drawing
editorialmatte, preventing a dark rectangle from range mismatch. All8cues and
30.5sduration retained; copyonly8x. Evidence layout-drag-continuity.json links
actualencodedmidframes for firsttable, additionaltable and roundtable gestures.
Finalpublish includes BOTH JPG and manifest-referenced WEBPposters.
