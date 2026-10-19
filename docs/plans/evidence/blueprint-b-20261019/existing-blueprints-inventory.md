# Existing canonical blueprints - read-only conversion inventory

All canonical backend blueprints were exported, including ended/hidden occasions
and blueprints unlinked from forms. No production write, migration or deployment
was performed. Scope is the user's explicit all-blueprint V2 cutover request.

Target assertions matched the persisted machine SSH skill, hostname, runtime
`FESTAPP_RUNTIME_DATABASE` and SQL `current_database()`. The connection used
explicit `BEGIN READ ONLY` transactions. All11 available tenant configurations
and current public activation documents matched canonical backend/generation1;
expected organizations exist and the three forced occasion links matched their
configured organization. The available activated configurations cover more
organizations than the four containing existing blueprints.

| Inventory | Count |
| --- | ---: |
| All blueprint rows |49|
| Organization3 /1 /7 /11 |22 /2 /24 /1|
| Linked occasion present |49|
| Ended occasions |42|
| Hidden occasions |10|
| Blueprints unlinked from forms |24|
| Geometry objects / existing stable spots |4516 /4516|
| Object/spot ID mismatch blueprints |0|
| Empty geometry with zero spots |5|
| Null objects / empty array objects |3 /2|
| Commercial groups |451|
| Nonempty background fields |18|
| Inline SVG / canonical public asset URLs |12 /6|
| Dimension profiles |10|

Every geometric record has type `spot`; basic configuration uses only
`dimensions.width/height`. Object keys are `id,x,y,type,group,title,state` and
group keys are `id,title`. All stable spot IDs, product IDs and inventory binding
IDs were exported without order/customer/ticket references, notes or tokens.
Stored object state labels include stale commercial presentation values; they
must not become a second order/hold authority during conversion.

The12 inline SVGs contain text, shapes and some local use references. No script,
foreignObject, embedded image, DOCTYPE or font-face was found. Six other
background fields are canonical public image URLs and require resource-byte
materialization instead of SVG-string parsing. Background and glyph appearance
still require the coordinator's actual conversion/rendering gate.

Private0600 artifacts outside the repository:

- `private-existing-blueprints.json`: complete49-row geometry/configuration/group/
  background and stable binding snapshot; each row has `conversionSourceSha256`.
- `private-existing-blueprints-index.json`: exact all49 IDs, per-row hash and
  geometry/background/link coverage for the reviewed conversion gate.
- `private-existing-blueprints-backgrounds.json`: per-background source hash and
  content classification.

These are under `/Users/miakh/source/festapp-blueprint-b-e2e-20261019/`.
Full export size1,133,539 bytes, SHA256:
`6eb22cb84ee7ff79604a99ebfb9f089e3657f941645e24b132deff28743d8553`.

Read-only catalog evidence: live `eshop.blueprints` has no `layout` column;
`eshop.blueprint_seat_bindings`, `public.blueprint_image_assets` and
`public.save_blueprint_layout_internal_v1(jsonb)` do not exist. The legacy
receipted blueprint update wrapper does exist. Integration B is not activated
on this live database. This inventory supplies a reviewed conversion input;
it does not authorize applying a converted bundle or claim visual parity.

## Form-unlinked ownership and background preparation

A second read-only live query verified all24 form-unlinked plans still belong to
existing occasions:23 occasions are open,22 ended,3 hidden. They retain232 spots,
with zero ordered spot references and zero currently active holds. Incoming
canonical blueprint foreign keys are exactly `forms.blueprint` and
`eshop.spots.blueprint`; similarly named columns in frozen import stage schemas
are separate retained datasets, not canonical foreign keys. There are zero
proven orphan plans, so none were deleted or selected for deletion. Ended,
hidden and form-unlinked status alone does not make a plan disposable.

All18 background fields were processed through the existing owned local Worker
and real Images/R2/registry, including bounded credential-free canonical public
reads for the six URL sources. All18 passed processed-byte SHA256, dimensions,
static raster format and ready registry acknowledgement. No alternate renderer
or Sharp transformation was used; Sharp only inspected resulting metadata.
Processed raster files are private0600 outside the repository for visual review.
The private manifest is `private-existing-blueprints-assets.json`, with entries
`assets[sourceBlueprintId].{asset,sourceSha256,rasterPath}`. The manifest explicitly
states `LOCAL_SYNTHETIC_ONLY`, occasion1; these are not production-ready registry
associations. Original SVG text references include Calibri/MSFontService/sans-serif
and Futura; exact font appearance remains a visual gate even though processing
succeeded. No production readiness or byte-identical future remote re-encoding
is claimed by this local artifact.

## Requested2025/2026 gallery activity metadata

A further explicit read-only snapshot exported public occasion titles/links/dates,
public form links/open flags, demo classification, per-plan2025/2026 non-storno
order/ticket counts and current occupied/used/active-held seat counts. No customer,
order/ticket ID, note, token or secret was exported. Sale year uses UTC
`orders.created_at` in `[2025-01-01,2027-01-01)`; both order and ticket must be
non-storno. Plan attribution deduplicates linked form and currently bound spot
order associations. These counts include non-storno pending/expired states;
they are not paid revenue or payment reconciliation evidence. Offering-year
classification uses occasion date overlap plus a linked form even with zero
sales; current open/hidden flags remain separate for the gallery's filters.

| Activity across all49 plans |2025|2026|
| --- | ---: | ---: |
| Plans with offering-date overlap |11|12|
| Plans with non-storno orders |14|13|
| Per-plan non-storno order counts |706|794|
| Per-plan non-storno ticket counts |1703|2169|

The union of non-demo sold/offered2025/2026 plans contains23 gallery cards.
One of all49 plans is demo. Current stable spot relationships show1120 ordered
non-used spots,2000 used spots and zero active holds. These use actual live
orders/tickets and deliberately differ from stale geometry `objects.state`.

The private0600 file is `private-existing-blueprints-activity.json` under the
same private evidence directory; SHA256
`1fb342a1a552b0171135aca59ef27b76fb07d82dbe45b38047816378965e1ad6`.
Original source bytes for all18 backgrounds are also persisted private0600 in
`private-existing-blueprints-sources/`; each exactly matches its previously
processed source SHA256. Asset manifest entries add `sourcePath/sourceMimeType`
for an offline original-versus-converted rendering comparison. No Flutter
command or production write was performed.

## All-source reviewed SQL replay

The disposable replay exercised all **49/49 actual-source layouts and 4516 seats**
through the private reviewed SQL migration and identical-command replay. Source
identities were mapped to synthetic local IDs; the source geometry and commercial
relationships remained the reviewed inputs. The run completed with full rollback.
`/tmp/blueprint-b-reviewed-replay.log` records:

> PASS 49/49 actual-source layouts through reviewed SQL migration + replay; 4516 seats; full rollback

Separate protected-state tests cover ordered, used and current held spots,
including NULL titles, source-hash/group mismatches, atomic rejection and the demo
migration/read-only boundary. This proves the prepared migration path against
actual source shapes; it creates no production bindings, receipts or assets and
replaces neither the Basic visual review nor production activation authorization.

## Native inline-SVG extraction supersedes bitmap conversion

The requested native structural conversion uses
`automation/blueprint_extract_svg_native.py`; it reads only private source files
and produces private0600 `private-existing-blueprints-native-svg.json` for all12
inline-SVG plans. Source hashes are checked before parsing. It expands SVG use
references and affine transforms, parses relative/absolute paths including
multiple subpaths and cubic/quadratic curves, and registers native geometry
through the actual centered-cover transform into the48-unit legacy cell frame.
No raster renderer, image transformation, production connection or Flutter
command is involved. Unsupported syntax produces explicit issues and prevents
structural completeness instead of silently discarding content.

All12 current source files are structurally covered. Tables are real editable
native tables with retained square/rounded corners and explicit appearance
styles; decorative geometry remains editable polygons/polylines/rectangles.
Source label fragments are preserved as native text and parented to their table
using inverse transforms; table auto-label is empty to avoid duplicate captions.
Text centers use the complete rotated affine transform. Source order receives
negative architectural z values, keeping chairs above architectural decoration.
The actual source zigzag points for plans27/91 are retained as native polylines
with the public zigzag editing properties.

Commercial-to-physical associations require a source caption and every existing
chair inside the expanded table bounds. Explicit review notes leave ambiguous
chairs in their original business group: plan5 group1, plans23/90 group22,
and plans27/91 group17. All source furniture remains present. Structural
completeness does not assert those associations or graphical/text-metric parity.
Calibri/Futura source font requirements are reported separately without inventing
font identifiers. The coordinator supplies the existing registered Futura font.

Focused offline checks passed the12-source corpus, affine multiplication order,
relative/subpath parsing, stable local identities, finite positive geometry,
flattened public node fields, real table binding targets, single parented labels,
corner overrides, architectural z order and four source zigzag polylines in each
of plans27/91. The coordinator/UI worker owns final public parser and rendered
visual checks. The earlier18-raster preparation is a source/reference artifact,
not the approved native inline-SVG conversion output.

## Final native reconstruction

The bitmap-backed candidate was rejected and superseded. Final49 documents have
4516 stable physical spots,18 fully native hall reconstructions,464 editable
tables, native captions and zigzags,17 dashed boundaries and zero raster
backgrounds. All real-font scenes compile without issues; the reviewed SQL
migration+replay49/49 passes with full rollback. Source palettes are document
styles, including purple and white exceptions, with mildly rounded table corners.
Ambiguous original commercial groups remain explicit reviewNotes and do not gain
invented distant table attachments. No original record was deleted or modified.
