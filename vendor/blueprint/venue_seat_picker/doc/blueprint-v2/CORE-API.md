# Stage A core API

Import `package:venue_layout_core/venue_layout_core.dart`. Pure Dart, no I/O, DOM, Flutter or host service. All documents and nested property collections are immutable. `fromJson` preserves unsupported schema in `UnsupportedLayoutSchema.original`; call `validateDocument` before accepting decoded documents. Document geometry is center based, clockwise degrees in y-down coordinates. Persisted values and scene numbers are quantized 1/1024; world composition uses full intermediate precision.

Frozen contract in CONTRACT.md remains supported. Additional implemented APIs:

Editor placement drafts may overlap, but new placements stay inside the canvas. The Flutter
controller keeps canvas dimensions fixed, validates structural integrity during
edits and boundaries, and exposes `placementIssues` / `showPlacementWarnings()` for explicit
save validation. Canvas growth is an explicit canvas operation only.

`moveLayoutWithinCanvas(document, ids, {dx, dy})` clamps a manipulation to the
fixed canvas while accounting for rotated subtrees and chair reflow. Oversized
objects cannot be inserted, and old out-of-bounds drafts can only improve their
existing overflow until repaired.

`reflowTablesAtCanvasEdges(document, tableIds)` reallocates automatic attached
chairs onto available in-canvas perimeter cells. Feed it the transformed gesture
baseline. IDs, count, metadata and fixed chairs are preserved; impossible fits
remain in the document for save warnings instead of silently losing capacity.

Layers are contiguous parent-first subtrees. Sibling `z` takes precedence across
object kinds; equal ranks use a deterministic kind/ID tie. `moveLayoutLayers`
moves a subtree to the front/back and `reorderLayoutLayers` moves it one step.
Hit testing uses the reverse canonical paint order. Each display item carries
`paintOrder: [nodeRank, withinNodeSlot]`, identical in full and partial scene
compilation. Consumers retain this order when applying presentation patches.
Temporary drag foreground is presentation only and never changes stored `z`.

- `worldMatrices(document)`, `localMatrix(node)`, `multiplyMatrix(a,b)`, `inverseMatrix(m)`, `transformPoint(m,x,y)`, `localHull(node)`, `worldHull(node,matrix)`, `nodeBounds(document,node)`, `selectionBounds(document,ids)`, `boundsOfPoints(points)`.
- `LayoutSpatialIndex(document)` caches one sparse world index; `.hitTest(x,y)`, `.query(rect)`. `hitTestRect(document,rect,{contained=false})` returns IDs. Rects use x/y/width/height. Hulls use List<List<double>>. Shape polygons use local `properties.points` arrays. `shapeFromPoints(shape, worldPoints,{id,properties})` materializes centered shape geometry.
- `transformNodes(document,ids,{dx=0,dy=0,rotation=0,cornerPivot=false})`, `resizeNode(document,id,width,height)`, `groupNodes(document,ids)`, `ungroupNodes(document,ids)`, `detachSeat(document,id)`, `attachSeat(document,seatId,tableId)`. All return immutable documents and reject locked subtrees/ancestors. Call transforms on the gesture baseline, with total world deltas. Group requires siblings and preserves world geometry.
- `fitCanvas(document,{padding=40})`, `resizeCanvas(document,width,height,{center=false})`; shrinking over objects throws.
- `backgroundPlacement(sourceWidth,sourceHeight,canvas,{fit='contain'})` returns centered uniform transform metadata. `fit='fill'` covers the canvas. Merge `assetRef` and `hash`. `registerTwoPoints(a1,a2,b1,b2)` returns similarity matrix; `registerBackground(background,a1,a2,b1,b2)` stores centered-image metadata from native pixel source points and world targets. Crop is a normalized source rectangle clipped in place while preserving image registration and uniform scale. Image scenes expose `sourceRect` and `destinationRect` maps `{x,y,width,height}`; source uses native pixels, destination is the corresponding centered local subrectangle, with identical sizes. Adapters consume these rectangles directly and apply `item.clip` in world coordinates.
- `rowLayout({rows=5,seatsPerRow=8,blocks=1,aisle=80,spacing=56,rowSpacing=64,x=100,y=100,arc=0,id})`, `busLayout({rows=10,left=2,right=2,rear=5})`, `compartmentLayout({compartments=4,seats=6,x=100,y=100,id})` return materialized editable documents. `reconcileAssembly(document,rootId,generatedFragment)` preserves IDs by semantic slot and manual overrides. `renumberSeats(document,orderedIds,{prefix='',start=1,step=1,labels})` returns preview document.
- `layoutCollisions(document)` returns overlapping physical ID pairs using sparse broad phase and triangulated exact hull tests. Furniture is physical. Decorations only collide if `properties.obstacle=true` or role `obstacle`. Ancestor/descendant hulls do not collide with each other.
- `fitSeats(document,{required area,count=20,spacing=56,rowSpacing=64,boundary,cancelled})` / `fitSeatsAsync(...)` return `LayoutFitResult` with `.document`, `.placed`, `.unplaced`, `.complete`, `.reasons`. `boundary` is an optional world polygon including concave rooms; complete seat hulls must fit. Existing obstacles stay fixed, seat sizes stay 40. Search scans fixed user spacing deterministically, caps at 100000 candidates. Async variant yields after each 8ms batch; UI should use this variant. `complete=false` means interrupted, not optimality. For ranked sampled spacing alternatives use `fitSeatVariantsAsync` below.
- `snapTranslation(document,ids,dx,dy,{zoom=1,grid,previousMagnet,disabled=false})` returns `.dx/.dy/.guides/.magnet`, thresholds 5/8 screen px, deterministic target IDs. Retain previousMagnet during gesture; snapping automatically uses a row parent's rotated axes; `axisRotation` overrides them explicitly. Guides include rotation.
- `savePreset(document,ids,title)`, `instantiatePreset(document,presetId,{x=0,y=0})`; clones remap identity references. Presets remain snapshots.
- `interpolateLayout(from,to,t,{reducedMotion=false})` uses shared cubic ease-out, shortest angle, stable identities. `layoutMotionTokens`: insert 160ms, reflow 200ms, camera 240ms, reject 160ms.

`compileScene` reports missing fonts/glyphs and emits no partial text object. Paths are materialized glyph outlines. Resources match CONTRACT.md, images are renderer-resolved. Furniture with a selection unit of child seats gets the unit count badge. Capacity badges come from host presentation capacity. Scene states include accessible labels and shared geometric icons.

`web/kernel/main.dart` exports global `VenueLayoutKernel` with JSON string inputs/outputs. Build to `web/dist/venue_layout_kernel.js`; no Flutter import. `web/src/index.js` exports `mount(container,{document,resources,seatPresentation,capacityPresentation,onSelectionRequested,onQuantityRequested,onIssues,assets})`, `update(handle, options)` and `dispose(handle)` plus handle methods. Resources assets accept `{data,mime}` base64 or explicit resolved URLs. Selection callback receives Set<string>, selecting boolean, resolves `{accepted,message}`. Quantity callback receives node ID and quantity. No synthetic business state is persisted in geometry.

Verification: `cd packages/venue_layout_core && fvm dart test`. Exact public JS parity: run `fvm dart run tool/parity_fixture.dart /tmp/venue-parity.json` in the core package; compile kernel from repository root, then `node web/kernel/parity_test.mjs web/dist/venue_layout_kernel.js /tmp/venue-parity.json`. Node executes the browser-compiled wrapper, while browser raster/interaction checks remain separate release gates.


Scene update/performance seam: `compileSceneNodes(document,ids,{resources,presentation})` returns only affected items, with immutable-document validation/world-transform caches. Remove previous items whose `nodeId ?? id` is affected and insert the patch items. `sceneItemBounds(item)` and each item's `bounds` provide conservative world AABBs (glyph control hull plus stroke); `cullScene(scene,viewport)` uses the same bounds. The JS wrapper exposes `compileSceneNodes(json,idsJson,resourcesJson,presentationJson)`, retains at most three decoded documents/two resource snapshots and hit indices, and the SVG adapter retains DOM nodes, patches affected nodes, preserves pan/zoom camera, and renders a 100-place roving accessibility window with set size/position metadata. Occupied places reject before callback; each async rejection restores only its affected selection unit.

Additional completion APIs: `fitSeatVariantsAsync(document,{required area,count=20,spacing=56,rowSpacing=64,minSpacing,maxSpacing,spacingStep=4,minRowSpacing,maxRowSpacing,rowSpacingStep=4,boundary,cancelled})` samples finite intervals (defaults ±8) with a shared 100000-candidate budget and 8ms asynchronous batches. Returns `LayoutFitVariants.variants/complete/tried`; each `LayoutFitVariant` exposes `result` (LayoutFitResult), `spacing`, `rowSpacing`, `deviation`, `key`. Ranked by placed count descending, deviation ascending, stable parameter key. Seat sizes never change. `nearestNode(document,fromId,direction)` with left/right/up/down returns the nearest directional spatial target by world centres, shared by JS roving focus. JS kernel exports nearestNode(json,id,direction).

`interpolateScene(fromScene,toScene,t,{reducedMotion=false})` caches correspondence between scene pairs and interpolates changed matrices/compatible paths only, reuses unchanged item references, and updates changed bounds. `layoutEaseOut(t)` is the shared cubic timing. Scene interpolation is paint-only; hit testing always follows the final canonical document.

The JS camera supports drag pan, wheel zoom and two-pointer pinch. No claim of hardware-specific performance is made by core unit tests; browser/raster QA owns that evidence. `layoutLimits` is the canonical numerical contract map for schema/tooling exports, including canvas/text/polygon/preset/crop/history/fitting limits.


Arrangement commands: `alignNodes(document,ids,alignment)` accepts left/right/top/bottom/centerX/centerY and uses complete world subtree bounds. `distributeNodes(document,ids,{horizontal=true})` preserves outer positions with equal gaps. Both reject locked selections atomically, preserve parent transforms, and ignore selected descendants of selected ancestors. `reorderNodes(document,ids,direction)` takes +1/-1 and moves within the same rendering band; `LayoutNode.copyWith(z:...)` provides explicit order.

Dashed/dotted outlines are compiled by core from `properties.dash` (positive lengths, [] solid) or `strokeStyle: dashed|dotted`. Core preserves the base fill path and adds an item `id: nodeId:stroke`, `nodeId`, `kind: stroke`, with fully materialized M/L path commands. Curves use pinned subdivisions (32 cubic/16 quadratic). Renderers draw the shared commands and do not independently measure, dash, or flatten curves. Stroke items preserve their source node's render band.


Data boundary hardening: canonical decoding requires explicit protocol/symbol version, canvas/defaultTextStyle/nodes, and each node's UUID/kind/center transform/dimensions. Missing or unknown geometry fields reject with `InvalidLayoutDocument.issues/original`; no legacy type/default-position recovery runs. The authoring constructor retains its documented defaults. `toJson` validates and rejects invalid documents with a typed failure. Validation is cached only by immutable document identity. Record arrays and JSON keys are serialized canonically; labels and text resembling UUIDs never get remapped as identity references.

All active document identity namespaces are disjoint (nodes, sections, units, generators, presets, optional attachment IDs). Attachments without IDs use their unique seatId identity per contract. Preset fragments have their own validated namespace and cannot contain nested libraries or split atomic units. Every relationship must resolve to its allowed node kind. Section titles/outlines, selection membership, attachment anchors, background similarity/crop/hash metadata, geometry properties and numerical budgets are validated. Opaque geometry extensions and business/session fields are rejected; host pricing/products/spots/orders/secrets stay outside the portable document. Cyclic/non-JSON/deep custom values reject before immutable copy. Unknown future schema retains its immutable original without conversion.

`layoutLimits.geometryAbsMax=1e9` is the approved finite-safe coordinate/size/angle magnitude bound; canvas sides retain 64-1e6. Finite 1e308 demonstrably overflows fixed-point multiplication, so finiteness alone is insufficient. Boundary failures use `coordinate_range` rather than overflowing VM/browser quantization.

`validateLayoutResources(snapshot)` validates the JSON safety, protocol and font geometry of resource snapshots at provider/import boundaries; it deliberately ignores the platform `images` cache. Image URL resolution is a host-provider responsibility. Portable demo import additionally verifies embedded raster MIME, dimensions, bytes and SHA-256 before mounting; the generic provider API also permits explicitly resolved URLs and does not apply that transport policy. Fonts require exact resource ID, SHA-256 source hash, positive finite units/ascent and finite nonpositive descent, one-codepoint glyph keys, nonnegative advances and bounded exact M/L/C/Q/Z command arity/finites. The browser wrapper exports `validateResources(resourcesJson)` returning JSON issues and validates each new cached resource snapshot once. Resource snapshots are immutable replacements; reusing the same JS object during status updates preserves resource/scene/DOM caches. Invalid JS document/resources updates reject before mutating the existing viewer.

Shared LOD data: glyph scene items include `minZoom=6/fontSize`; `sceneItemVisible(item,viewport,{zoom=1})` and `cullScene(scene,viewport,{zoom=1})` apply the same threshold and world AABBs. Both adapters use effective logical screen scale, without DPR multiplication. Exact full scene parity retains all original glyph outlines; LOD only controls presentation.


Protocol v1 metadata maps are closed: canvas accepts only x/y/width/height/fill; document text style only fontId/size/color/align/lineHeight/bold/italic/fontStyle; background only assetRef/hash/x/y/rotation/width/height/scale/opacity/crop and crop only x/y/width/height. Generator records accept id/kind/rootId/assemblyId/nodeIds/parameters/version; optional version must be1, both root aliases cannot disagree, and parameter names/types follow the supported table/row/bus/compartment scalar contract. Unknown fields reject as `unknown_field` with the original immutable import payload preserved. Future extension requires a versioned contract change rather than silently storing or dropping unsupported fields.


Object label readability: seat/table/furniture/capacity/shape symbols keep their full parent/child rotation; their labels use a world-upright translation-only matrix at the same world centre and centered glyph outlines. Explicit text nodes retain the user's composed rotation. Count badges remain world upright below the world outline bounds. This is shared core scene geometry, so neither adapter counter-rotates or repositions native text.


Desktop arrangement additions (2026-10-18): `snapTranslation` infers equal
edge gaps from consecutive aligned table bodies, supports continuation and
insertion between tables, and emits ordinary axis guides with optional
`kind: spacing` and `spacing` metadata. Occupied slots and unrelated rows are
excluded. The editor supplies an 8-unit fallback grid; attraction is at most
2 screen pixels and 20% of the interval, after object/spacing magnets.

The editor selects table chairs directly; table-body selection still moves the
complete assembly. Independently transformed attached chairs retain their IDs
and parent and become manual placements. Their local position is preserved
inside the canvas; an attached, unlocked manual chair may relocate when its
table reaches an edge. Manual is a placement preference, not a boundary lock.
`copySelectionToClipboard()` writes a versioned geometry-only selection;
`pasteSelectionText(text)` and `pasteFromClipboard()` clone all identities and
relationships, fit the assembly within the fixed canvas, and produce one undo
transaction. Repeated paste offsets increase. Web uses native paste events
(Windows/Linux Ctrl+V, macOS Cmd+V), without requesting clipboard-read permission;
editable text keeps native text clipboard behavior.

Desktop host APIs: `VenueLayoutController(document, {tableLabelPrefix = 'Table'})`
allocates unused numbered table names on insertion/paste/duplication;
`nameInsertedTables(fragment, {defaultTablePrefix})` prepares stable preview
labels. `duplicateSelection({dx = 40, dy = 40})` supports zero-offset gesture
copies. The editor starts a history gesture before Ctrl/Meta duplication, then
moves only new IDs from a stable baseline; commit and cancel include creation.

`VenueLayoutLocalizations.delegate/supportedLocales/localizationsDelegates`
provide Flutter-native English and Czech catalogs with English source fallback.
The combined delegates include Material/Widgets/Cupertino translations.
`VenueLayoutStrings` optionally overrides host terminology. Template factories
accept `localize: resolver`; `localizeLayoutDefaultLabels(document, resolver)`
translates stock names, text, section titles and selection-unit labels while
preserving all geometry identities, level keys and arbitrary custom labels.


Row geometry correction (2026-10-18): `rowLayout` persists rows, seatsPerRow,
blocks, arc, spacing, rowSpacing and aisle. Chair tangent angles use
`atan(2 * arc * (seatIndex - midpoint) / spacing)` so angular geometry is in
world-distance units. `rowLayoutParameters(document, rootId)` returns these
settings and can infer omitted legacy settings from nonmanual materialized
slots. `repairLegacyRowTangents(document)` explicitly repairs only matching
legacy generator positions/angles while retaining custom, manual and locked
placements, root transforms and all IDs. The demo applies this repair to its
recovered draft and saved baseline.

Row counts are directly editable in the inspector with integer inputs and
add/remove row/column buttons. Advanced settings expose curvature, seat and
row spacing, blocks and aisle width. Reconciliation retains semantic seat IDs;
each edit is one undo transaction and cannot silently enlarge the canvas.
Ordinary wheel scrolling now zooms at the pointer regardless of selection;
Shift-wheel pans, with trackpad pan/pinch and the hand tool also available.


`hitTest(document,x,y,{tolerance})` and the spatial index counterpart accept an
optional world-distance tolerance for open paths; default physical behavior is
unchanged. The editor supplies `8 / viewportScale`. Broadphase uses actual path
segments and arrowheads, including neighboring cells, followed by exact finite
segment/endpoint distances. Closed filled shapes keep their original policy.
`resizeNode` scales explicit path vertices. `updatePathVertex(document,id,index,
localX,localY)` normalizes bounds and parent-space position while preserving
untouched world vertices, identity, transform rotation and styles.

`VenueLayoutController.attachChairToTable(seatId,tableId)` preserves the seat ID,
reparents/attaches it, repacks the table perimeter and enforces fixed-canvas,
capacity, lock and host constraints. Editor drop creation/reassignment uses the
same gesture as attachment, so rejected capacity drops leave no orphan seat.

`rowAssemblyBounds(document,rootId)` returns the actual descendant hull bounds
in the row root's local coordinate system, excluding the group's placeholder.
`resizeRowAssembly(document,rootId,width,height)` retains the root transform and
canonical generator origin while adjusting spacing/curvature. Chair dimensions,
identities, styles, manual placements and references remain intact. Requested
sizes clamp to physical footprints; collisions with manual overrides or locks
reject atomically. Callers anchor the opposite handle using actual old/new local
bounds, including any change to their x/y. Canvas policy remains in the controller.

`canAttachSeatToTable(document,seatId,tableId)` trials the exact atomic attachment
operation. `reflowTable` reserves manual/locked footprints and metadata, packs
remaining chairs without chair-chair or chair-table overlap, or rejects without
partial changes. Attachment also constrains the target/chairs to the fixed canvas.

`resizeNode(...,{protectedSeatIds})` reduces table chair count to the new physical
capacity, retaining protected identities before free seats. `reflowTable` accepts
the same optional host-owned set for explicit count edits. If protected/atomic
units cannot fit, `TableResizeRejected` aborts without changing geometry. Removal
cleans live attachments/selection units/generator references without mutating
independent preset snapshots. Enlarging a table does not create seats.
`VenueLayoutController.protectedSeatIds` is a live host callback, intentionally
separate from portable geometry, and also guards generic removal and history.

`resizeObject(id,width,height)` is the guarded controller inspector command.
UI round-table aspect locking is default; Shift bypasses it. Core dimensions are
explicit and allow elliptical geometry. Error and removed-seat notices overlay
the canvas without changing its frame or camera.

`reflowTablesAtCanvasEdges` uses physically spaced side/end slots with complete
packing before committing. Unlocked manual positions are preferred; a wall may
relocate them when necessary. `snapAttachedChairPosition(document,seatId,
{tolerance:32})` chooses a nearby unoccupied, in-canvas standard slot and matches
its orientation/attachment coordinates. Far manual positions remain untouched.

`couchLayout`, `couchSeatCount`, `resizeCouchSeats`, `resizeCouchBody` and
`isCouchNode` are canonical furniture operations. Cushions are materialized seat
nodes in one stable atomic unit; existing seat/unit IDs and host references stay
intact. Count changes preserve current cushion width and grow/shrink the body
symmetrically around its existing center; body resizing clamps minima without
growing the canvas. `protectedSeatIds`
freezes protected atomic membership in both directions. Controller acceptance
and history also protect atomic unit membership. Couch render details use shared
ordinary scene paths; cushion presentation colors override stored upholstery.

`insertPathVertex(document,id,segmentIndex,localX,localY)` and
`removePathVertex(document,id,index)` normalize bounds while preserving untouched
world vertices under rotated/nested transforms. Insertion converts a line into
a polyline and retains arrow/polygon shape. Minimum counts, locks, finite values
and the512vertex/document budgets are enforced atomically.

The editor exposes immediate drawing pointer taps separately from delayed
selection/double-click activation. Live hover tails are previews, excluded from
the final path. Draft vertex markers and drawing actions overlay the canvas so
starting a drawing does not change its viewport. Midpoint insertion plus dragging
uses the post-insertion normalized document as the gesture baseline.

Rectangular wall reflow preserves feasible side memberships, transfers blocked
short-side chairs to the opposite side first, then centers equal-pitch side rows.
Preferred spacing matches the normal generated row; compact spacing is a fallback
for clipped canvas intervals. Fixed manual/locked seats remain authoritative.
Already-contained wall drafts can be normalized by a zero-delta bounded move;
normalization is idempotent and never changes chair count or identity.

Regular zigzags use `zigzagLine(startX,startY,endX,endY,{teeth,amplitude,id,properties})`
and `updateZigzag(document,id,{teeth,amplitude,start,end})`. Update endpoints are
in the current local frame. `isZigzagNode` identifies their materialized polyline
geometry. Tooth count is 1-255; amplitude is half the peak-to-peak height. Endpoint,
parameter and resize edits regenerate regular peaks while retaining identity,
styles and transforms. Freeform vertex edits clear the pattern metadata.

Global appearance lives in optional immutable `document.appearance`, keyed by
`table`, `seat`, `shape`, `furniture`, `capacityArea`, `text`. Values whitelist
`fill`, `stroke`, `strokeWidth`, `cornerRadius`, `opacity`, `color`.
`effectiveNodeProperties(document,node)` merges local properties, global type
style, then explicitly listed local `appearanceOverrides` keys.
`setLayoutAppearance(document,kind,patch)` merges a validated global patch.
`setNodeAppearanceOverride(document,ids,keys,{enabled})` captures current effective
values when enabling local exceptions and restores inheritance when disabling.
Open paths remain transparent; transient seat presentation overrides appearance.
Global edits leave node geometry/identity/attachments/units untouched. Empty
appearance is omitted from JSON, preserving existing documents; nonempty style
roundtrips through the portable bundle and JS kernel. Fonts remain governed by
`defaultTextStyle` and existing node text properties.

Appearance also supports `seatStyle: plain | wood | upholstered` with strict enum
validation. Wood/upholstered seats have distinct canonical silhouettes and
construction details inside existing bounds. Parts share the seat identity; no
additional data entities or independent hit targets are created. Sofa cushions
retain their furniture treatment; selected/occupied/pending states keep priority.
VM and compiled-JS full/partial scenes share the same canonical paths.

### Selection and appearance preview behavior

The inspector close control clears the editor selection and canvas-edit mode;
Escape also cancels the current gesture/tool before clearing selection. Text
editors retain their own Escape cancellation. Neither clearing selection nor
previewing styles creates document history.

Appearance previews compile small, cached specimens through `compileScene` and
`LayoutScenePainter`, with the current document theme and font resources. They
never compile the entire working plan or mutate its nodes. Chair material cards
preview each material using the current colors. Used-color collection in the
inspector runs when the color dialog opens, rather than on every drag update.

### Shared incremental Flutter rendering

`LayoutSceneCache` is a derived-data adapter used by the shared editor/viewer/
picker surface. It detects changed immutable nodes, includes their descendants,
and combines geometry and presentation updates through `compileSceneNodes`.
Unchanged scene items retain identity, so painter path caches remain useful.
Node addition/removal, hierarchy/kind/layer changes, global style/font/background/
canvas changes and resource replacement use full canonical compilation. Compiler
issues also use the full path; invalid snapshots never leave stale valid items.
The adapter owns no geometry rules and does not modify the document.

The core exposes `sameLayoutValue`, `sameLayoutNode` and `sameLayoutDocument` for
consistent semantic comparisons. The controller retains immutable selection
snapshots and an immutable saved baseline; dirty/no-op checks avoid serializing
the entire document during pointer updates. Selection getters are constant time,
and callers holding an older snapshot never observe later selection changes.

### Coordinated appearance families

Appearance offers Modern, Timber, Lounge, Transport and Traditional hall.
They set explicit per-kind `objectStyle` (simple/wood/lounge/transit/hall), matching seat style,
corner treatment, outline weight and opacity in one controller command. They
preserve colors, canvas dimensions, geometry, IDs, memberships and explicit local overrides.
Each family also selects a subtle floor pattern; the floor can be changed independently.
Color palettes remain a separate command and preserve the chosen appearance.
Existing and newly inserted objects resolve the same document theme.

The primary choices show canonical composite specimens with chairs, a table and
a couch. Object-specific numeric controls live under Fine-tune appearance. The
material family is persisted as validated appearance data, never inferred from
its translated label or stored as a bitmap. Copy-style and opting out of global
appearance also retain `objectStyle`.

### Bars and stools

`barLayout({count:0,width:280,height:72,guestSide:'bottom',x,y,id})` creates a
`table` subtype with `properties.furniture: bar` and strict `guestSide`
(top/right/bottom/left). `isBarNode`, `barSeatCount`, `reflowBar` and
`setBarGuestSide` expose the subtype without a parallel geometry authority.
Seats remain ordinary stable `seat` children/attachments, marked furniture:stool
when generated; a seat attached to a bar also renders as a stool by parent.
There is no atomic customer selection unit: stools can be booked individually.

Capacity, automatic reflow and wall candidates use only the guest side. The
opposite side remains free for staff. Moving a bar clamps the whole footprint
including stools to the canvas; it does not transfer them to another side.
Changing guest side preserves IDs/count, rejects a side without sufficient room,
and uses one controller transaction. Resizing reuses table protected-seat rules.
The inspector exposes guest side, normal seating count and dimensions. Bar names
are localized and copying uses the existing intelligent table-name allocator.

The counter has a visible service/guest-edge treatment; stool silhouettes and
counter details follow Modern/Timber/Lounge. Colors remain inherited from table
and seat appearance independently of subtype. Round table rims also preserve
both axes' proportions, and wood round tables replace plank seams with a small
circular mark placed clear of upright labels.


### Floor material and camera limits

Optional `canvas.floorStyle` is a closed enum: `plain|wood|tile|carpet`.
Omission remains plain for existing documents. Modern/Timber/Lounge select
respectively tile/wood/carpet without changing the color palette. A custom
background image takes precedence over generated floor patterns. The compiler
emits one non-interactive `floor` path before objects, with an adaptive bounded
segment budget; both renderers consume that same path. Floor changes invalidate
the scene through canvas metadata, while pointer movement retains cached paths.
The editor grid is drawn above the floor and below objects.

Editor and web viewer cameras use a minimum of 90% of whole-canvas fit and
bounded translations. Large wheel/pinch input cannot lose the plan or shrink it
indefinitely. Flutter reads the XY matrix scale, excluding the unchanged Z axis.

### Transport assemblies

`busLayout({rows:10,left:2,right:2,rear:5,decks:1,upperRows,upperRear,x,y,id})`
creates an editable schematic with body, windscreen, driver, doors, windows,
aisle and double-decker stairs. Two decks share physical body dimensions and
appear beside each other. Rows and rear counts are independent per deck.
`compartmentLayout({compartments:4,seats:6,x,y,id})` includes body, corridor,
partitions, facing seats and door markings. Templates and palette insertion use
these canonical factories rather than separate sets of loose seats.

`busLayoutParameters` / `compartmentLayoutParameters` expose saved or inferred
legacy counts. `updateBusLayout` / `updateCompartmentLayout` reconcile one
immutable document and preserve existing IDs, labels and manual exceptions.
Removing manual, locked, protected or part of an atomic set rejects atomically.
Seat children retain explicit deck and stable side/row/slot metadata, alongside
normal parent relationships. Decoration children redirect selection to their
assembly; they are never customer booking entities. Single seats remain
independently bookable, including across two decks.

The schematics are configurable generic arrangements, not certified vehicle
plans. Design reference: [Setra S 531 DT](https://www.setra-bus.com/int/en/models/tc-dt-models.html)
(two decks, stairs and configurable lower-deck facilities). Actual transport
providers must enter the layout appropriate to their vehicle.


### Sketched and extensible surfaces

New bars default to a seatless polygon. The palette and inspector do not offer
bar stools; previously authored explicit stools remain readable and protected.
Tables and bars share the standard polygon path, scene compiler, hit contour,
resize and vertex editing contract. No second furniture/seat identity tree is
introduced. `surfacePresetPoints` supplies rectangle/L/U outlines.
`sketchSurface(centerline,{breadth,bar,id})` expands a sketched centreline into a
closed footprint with bounded mitres and self-intersection rejection.

The dedicated Paint table / Paint bar tools join complete cells under a held
pointer. Each virtual cell is a 100 x 100 unit four-seat table module. The
painting grid uses this same spacing, independently of the normal 8-unit editing
grid. It appears only after pointer-down/drag begins and is anchored to that
gesture: the first module is centered at the start point (clamped at canvas edges). Fast pointer motion fills intervening cells. Releasing commits one polygon
and one undo step; unpainted enclosed regions remain holes. Grid cells are
transient and are not stored as separate objects. A plus handle on each edge starts `extendTableSurface`: it adds a
shouldered branch following the pointer in the root's coordinate frame. Existing
vertices can be dragged independently. Each completed gesture is one undo step.
`surfaceFromPolygon` converts an already drawn polygon using the same identity.
`reshapeTableSurface` applies an L/U/rectangle outline.

`reconcileSurfaceEdit` preserves child world positions during outline recentering
and routes seating through protected table reflow. Polygon seating samples safe
outward normals, rejects collisions in concave recesses, and uses the existing
perimeter attachment contract. Slots are cached per immutable node and bounded
to 512 candidates. Reservation IDs are never replaced; a destructive edit that
cannot retain protected seats rejects atomically.

`layoutMaterialFamilies`, `layoutMaterialAppearance` and
`withLayoutMaterialFamily` now own material data shared by templates and UI.
The additional transit family has shaped seats, headrests and armrests, while
booking-state colors continue to take priority. Transport schematics include a
front-facing travel arrow. Template library v2 provides three styled balls,
cinema, theatre with balcony, conference/reception, single/double-deck buses,
carriages and retained balcony/lounge/blank presets.


Polygon tables and bars use the active material family in the shared scene
compiler. Their inset rims follow the concave outline and holes, rather than
scaling a bounding box; wooden joints are clipped to filled scan intervals.
The decorations do not change the persisted outline, seats or hit geometry.
`reflowTablesAtCanvasEdges` also considers nearby physical objects through the
spatial index. A moved table's chairs choose unobstructed perimeter slots while
stationary neighbours remain unchanged. Bounded movement rejects a proposed
position if a complete chair arrangement cannot fit. Reserved identities remain
stable, and locked chair positions are preserved.


Custom polygon tables and bars use the family corner radius in their canonical
quadratic outline, including concave bends and holes. Local tangent lengths are
capped at half adjacent edge lengths, preventing oversized radii from inverting
short segments. Authored vertices, seat attachments and collision footprints
remain unchanged; rendering and hit contours share the rounded path. Material
rims offset the same radius. Painted bar modules are 60 units wide, compared
with 100 units for four-seat table modules; the temporary grid follows the active
furniture width and retains its gesture-relative origin.


### Original scout hall template

Template library v3 adds `scout-ball-182`, using the selected Skautský ples 2026
reference: 31 tables, 182 seats, 29 six-seat and two four-seat tables (18/19).
All original seat labels, lattice positions and memberships are retained on the
32 x 32 lattice at 100 world units per cell. The reviewed 3000 x 3000 raster
footprints become native editable room, stage, entrance, two column obstacles
and table rectangles; no raster asset or network fetch is needed at runtime.
Every creation allocates fresh node/attachment/section identities. Source
product, reservation, state and database identity data are excluded by the
extractor. Explicit seat positions are manual attachments and are not reflowed
when the template is created.

`tool/import_scout_reference.py <private-snapshot>` regenerates the geometry-only
Dart constants using `tool/fixtures/scout_hall_geometry.json`. That file records
the reviewed original raster edge positions and source image SHA256. The raster
and private source snapshot remain outside the distributable. The `hall` family
uses timber construction with 14-unit corners and a plain floor, independently
of the template's ivory/sage palette. Choosing a template resets the editor's
viewport so the entire new canvas fits immediately; ordinary edits retain the
current viewport.

### Scout balcony hall and section selection

Library version 4 adds `scout-ball-balcony-249`, the second Skautský ples 2026
(6 February). The original 28 x 52 lattice is normalized to 2800 x 5200 units.
All 249 original labels and group memberships are retained. The original SVG
contains 21 table outlines; source group 22 is a separate 15-seat cluster without
a table surface. Its seats remain children of that group, while 234 table seats
have explicit edge attachments. Hall and balcony are separate organizational
sections. Every creation allocates fresh node, attachment and section identities;
source reservation states, product links and database IDs are not imported.

`tool/import_scout_balcony_reference.py` consumes a sanitized structural snapshot,
checks capacity/group counts and exports seat coordinates and original SVG table
bounds. Both reference halls use `addReferenceHallSeats` to preserve world-space
seat registration, including rotated balcony tables, through one implementation.

The `banquet` appearance family (Slavnostní sál) combines upholstered seating,
timber table construction, a plain floor and softened corners. It uses the same
family registry and scene compiler as editor previews and the web viewer.

Editor selection treats a section root as organization, not as an atomic object
group. Clicking a direct child selects that object, Shift toggles it, and attached
table seats remain independently selectable. Ordinary object groups stay atomic.

### Table relationship feedback and banquet chair construction

Selecting a table now adds editor-only seat relationship feedback: subtle outlines
on its attached seats, short dashed connections from the table perimeter to each
seat perimeter, and a plain inspector explanation. Relationship feedback never
adds chairs to selection, selection bounds, resize targets or persisted document
nodes. It follows explicit attachments, with parent membership covering existing
unattached table children, and supports rotated, round and polygonal surfaces.
Connections use the scene's quantized world transforms; camera-only frames repaint
without recompiling geometry. Handles stay on the tabletop and seat dimensions
retain the established table resize/reflow policy.

`seatStyle: banquet` is now a distinct shared-core chair construction, used by the
banquet family and scout balcony template. It has a tapered padded seat, two back
supports and a separate bowed back rail, plus an inset stitch seam. It reuses no
lounge chair silhouette. The same paths define editor/viewer painting and core hit
geometry; accents add no separate seat identities. Existing explicitly authored
`seatStyle: upholstered` exceptions remain unchanged.

### Original minimal scout presentation (template library version 5)

Both reference scout templates now reproduce the original minimal floorplans,
using the existing `simple` object style and `plain` seat style. They no longer
apply the hall or banquet material families. Source hall 182 retains white
rectangular tables, black outlines/type, the grey stage and blue columns. Source
hall 249 retains sage tables, grey floor, blue balcony, stairs and its original
`Stůl N` labels. Seats use the existing V1 available marker: a green rounded
rectangle, 77.5 units in its 100-unit cell, with 20-unit corners and no outline.
These are ordinary V2 node geometry and appearance values, not an image overlay.

The optional node property `labelOrientation` accepts `screen` (existing default)
or `object`. It lets the original balcony labels follow their vertical tables
without changing default upright labels elsewhere. The shared scene compiler
applies it identically in Flutter and JavaScript, including partial scene updates.
Original seat positions, memberships and fresh V2 identities remain unchanged;
source reservation states are not part of the template.

### V1 selection feedback and physical table seating

Customer selection is rendered once in the shared core: a green marker enlarges
from the V1 normal inset to the V1 selected inset and displays a centered white
check. The check stays upright at every chair rotation; corner radii and authored
hit geometry remain stable. Pending selection keeps the same check, prevents repeat
requests and rolls back only its own IDs on rejection/error. Flutter customer
pickers do not draw editor selection outlines. Explicit live `selected` booleans
synchronize initial/updated ownership in both adapters; status-only patches preserve
local selection. Deselecting an initially selected seat immediately clears its
visible check rather than falling back to the old presentation value.

`minimal` is an existing-vocabulary basic family (simple table outlines, plain
markers, plain floor), alongside the `Original` color palette. Default new classic
ball templates use `withLayoutMinimalStyle`. The sparse document constructor and
`empty()` remain unchanged, preserving authored node styling for existing callers.
Color palettes remain separate from material geometry families.

Table node properties `seatWidth`, `seatHeight`, `seatGap`, `seatSpacing` and
`seatEdgePadding` define physical seating independently of appearance. Dimensions
must be positive; distances nonnegative; all are finite and bounded. The defaults
retain existing 40-unit chairs / 52-unit pitch behavior. Reference halls explicitly
use 77.5-unit chairs, 11.25-unit table clearance and 22.5-unit chair spacing.

`TableSeating.fromDocument` infers older documents' chair sizes from the predominant
attached footprint and their attachment gaps. Count additions and incoming loose
chairs use the table's metrics; palette chairs and new tables follow the prevailing
physical scale of the current document. The same metrics drive capacity, rectangular
and round perimeter slots, polygon slots, canvas clipping, snapping and side-row
centering. New positions are checked against other chairs, the table and nearby
physical objects. A rejected operation leaves the input and IDs unchanged.

`configureTableSeating` updates a table and reflows its existing seat identities in
one operation; controller history makes it one undo. The inspector's collapsed
`Chair layout` section exposes width, depth, table clearance and chair spacing.
Reservation state remains host presentation and never enters these geometry fields.

Palette assemblies use the current document's physical chair profile, independently
of appearance families: couch cushions match its width/depth, rows scale spacing
and retain their dimensions when regenerated, and vehicle schematics scale their
partitions, aisles and labels together with the seats. `rowLayout`, `busLayout`
and `compartmentLayout` accept optional `seating`; existing callers retain the
40-unit defaults. Vehicle count edits infer the assembly's own chair profile.
Palette preview caches invalidate when the physical seating profile changes.

Controller insertion and canvas drag previews raise new root subtrees to the
front through `moveLayoutLayers`, preserving internal stacking and stationary
layers. The complete insertion remains one undo operation.

`VenueLayoutController.previewMove` owns constrained drag translations. A rejected
placement retains the last valid preview instead of rendering the gesture origin;
returning the pointer to the origin still restores that valid original position.
The core move already reflows chairs, so this path skips a redundant table reflow
while retaining document, reservation, lock and canvas acceptance checks. Ordinary
`apply` continues to repair table placement for unconstrained callers.

Couches retain their original physical cushion minimum in `seatWidth` and
`seatHeight`. Body resizing clamps to these minima plus upholstery insets; growing
the body does not raise the stored minimum. Legacy couches infer their minimum
from existing cushion dimensions on their next rebuild. Seat identities and
atomic reservation membership remain unchanged.

The shared Flutter canvas retains the primary pointer-down position until drag
recognition. Hit testing and the translation baseline use that position even if
the cursor has already crossed the object boundary before recognition starts.

Palette click and drag insertion now share one constrained preview/commit path.
The immutable combined fragment is cached for that gesture. An infeasible move's
baseline return is never published as an origin-position preview; rejected release
cancels the entire insertion without a history entry. A later valid preview or
new insertion clears stale feedback and remains usable. Constrained table placement
checks both its body and chairs against nearby physical furniture; decorative text
and background shapes remain nonblocking. Placement feedback uses the package/host
localization boundary, including parameterized capacity and locked-object errors.

Movement rejects a physically blocked tabletop before generating chair perimeter
candidates. The accepted path shares its spatial index with the existing reflow
implementation. This leaves wall fitting and chair identity rules unchanged.
`tool/drag_overlap_benchmark.dart` measures the scout hall's blocked/free movement
paths with 30 warmups and 60 recorded samples per path.

Palette drag feedback is visible outside the canvas and for blocked positions.
A notifier hands visual ownership to the canvas for valid positions; invalid hover
removes the previous inserted preview once rather than leaving it behind. The original immutable fragment is
retained for recovery, so re-entering free space does not allocate another object.

Palette feedback has three derived visual states: floating outside the canvas,
canvas-owned valid placement, and blocked placement. A blocked placement keeps a
translucent object at the cursor with a theme error outline, prohibition icon and
localized `Cannot place here` badge. It never adds invalid geometry to the document
or shows a duplicate canvas preview; recovery reuses the same fragment.

SVG wheel zoom uses the Flutter editor's 200-pixel exponential distance. The SVG
viewBox scales by `exp(deltaY / 200)` (inverse of Flutter's scale), retains the
world point under the cursor, and preserves existing fit/zoom limits and Shift pan.

Wood/hall and lounge chair construction is a simple seat plus one backrest.
Wood omits legs, posts and joints; lounge omits concentric inset rings. A shared
rounded contour drives body, accent and hit geometry; the existing back-direction
rules still orient chairs correctly around tables. Authored dimensions and node
identities are unchanged, and both scene consumers receive the same simplification.

The `round` material family uses `seatStyle: round`: one circular marker, sized
to the smaller authored chair dimension, with the same contour for rendering
and hit testing and no construction accent. It preserves physical footprints,
seat IDs and palette colors. The editor offers minimal, wood, lounge, round,
banquet and transit families; stored simple/hall appearances remain readable.

Lounge also supports `seatStyle: roundUpholstered`: a circular upholstered
seat plus the same simple backrest. It shares scene and hit geometry across
renderers. The Lounge card offers soft-corner/round variants without adding
another family; applying Lounge after Round seating retains the circular seat.

Round lounge uses a centered circular cushion and a concentric wraparound
back/arm shell with rounded ends. Both fit the smaller authored dimension;
body and accent share the same shell contour and back-direction rules.

Renderer parity: zero or missing stroke width disables the outline (Flutter
must not interpret zero as a device hairline). Item opacity multiplies each
fill/stroke paint in both renderers; image opacity remains per image. Authored
labels use minZoom 0 so canvas-fit views keep the same plan annotations.
Round material seats request an explicit 1-unit outline, preserving palette
stroke colors; minimal seats still request no outline.

Attached seats face the tabletop by default, including manually moved seats.
The canonical world matrix uses the circular table center or nearest edge of
a rectangular/polygonal surface. Body, accents, hit geometry and both clients
share this orientation. Explicit user rotation sets the boolean node property
`manualRotation: true`; subsequent movement respects that angle. `manual` still
means a protected manual position, independently of rotation. Detaching retains
the visible world pose. Rotation controls display the effective local angle.

`configurePlanTableGap(document, gap)` authors one global table-chair gap
change through the canonical perimeter packer. It preserves chair identities,
physical dimensions, explicit rotations and manual positions, skips locked
assemblies and bars, and rejects infeasible layouts atomically. The persisted
`appearance.table.seatGap` (0-1000000) is an authoring default for future tables,
including empty plans, independent of material/color choices. Existing physical
profiles remain authored on tables; effectiveNodeProperties does not substitute
this default for a table-local seatGap. Renderers consume authored positions.

Shared Flutter editor UI exports EditorNumberScroll for numeric TextField and
TextFormField controls. Wheel input is owned only by the focused field under
the pointer; it uses EditableText.userUpdateTextEditingValue so normal form
callbacks and validation run. Hosts can commit through onChanged; min/max and
step are explicit, Shift multiplies the step by 10, and unfocused/read-only
fields leave panel scrolling alone. This adapter is also used by Festapp ticket
canvas dimensions and margins.

Circular/oval table anchors use arc-length sampling projected onto the exact
ellipse, with two coordinate quanta of numerical clearance to avoid false
overlap at zero gap. Preferred equal spacing is tried first; fallback slots
are ranked lazily by deviation from each regular target. Compressed automatic
round-table layouts return to regular spacing when a move frees their preferred
positions. Fixed manual positions and explicit rotations retain their rules.
Timber and lounge seat fronts reach the authored front edge so zero gap also
means visible contact; round lounge cushion and shell stay concentric.

Global chair controls use `configurePlanTableSeating` with optional width,
height, gap, spacing and edge padding. Only supplied settings change existing
unlocked tables; chair IDs, manual positions and explicit rotations survive.
Locked assemblies keep their local physical profile. Defaults persist under
`appearance.table`, drive `documentSeating` for future insertions, and never
mask existing geometry. `configurePlanTableGap` delegates to this operation.
The style gallery precedes a collapsed chair section. Slider drafts update only
the small scene specimen; release applies the entire plan atomically in one undo
step. Exact numeric and focused-wheel edits remain available.

Chair controls expose linked size and table gap first, with independent width,
depth, spacing and corner padding under advanced settings. Slider double-click
restores the canonical TableSeating factory value in one undo step. A separate
preview count (1-24) uses real core reflow on a fixed 260 x 150 specimen. Capacity
and collision limits reduce the rendered count with a visible warning; the
simulation never grows the table or changes the user's document/history.

Round and round-lounge chair geometry scales independently along authored width
and depth. Round seats become ellipses when dimensions differ; lounge cushions,
wraparound shells and end caps share the same normalized geometry. Equal
width/depth retain the original circles. Scene, picking and collision outlines
consume this single geometry for both Flutter and the shared web kernel.
