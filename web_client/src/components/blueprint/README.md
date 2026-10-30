# Blueprint public selection

`blueprint_selector.js` owns the dialog lifecycle and mounts the public `@festapp/venue-layout` renderer. `BlueprintLayoutAdapter` projects the canonical layout and public bindings into presentation and forwards selection to the existing form session. Standing quantities use the existing ticket product fields.

The package loads its unchanged kernel asset through `loadKernel`; `loadLayoutAssets` validates processed image metadata and bytes. The host does not render raw SVG or implement geometry, gestures or transforms. Closing aborts loading and disposes the shared mount. Missing canonical geometry is a repairable load error, never a legacy renderer fallback.

At minimum zoom, another zoom-out recenters a panned plan at the same scale.
The shared renderer owns wheel, pinch and `zoomBy` behavior. Its `canZoomOut`
state keeps the host minus control enabled while recentering is available.

Financial operations, hold ownership, limits, products and order payloads remain in the form/session/server owners. Public presentation never includes administrator customer or order metadata.

`select_spot` owns the complete atomic hold and its original expiry. Checkout
requires unique seats from the form's blueprint and a matching non-null hold;
SQL rechecks form scheduling and expiry against its current clock after locks.
Successful sale consumes the hold. A verified editor's replacement keeps the
same order/history owners and cannot erase another buyer's active hold.

Reopening replaces local selection with the server projection and restores its
own `expiresAt`; retries retain the frozen command ID and input. Public `data` is
an empty allowlisted object. Product rows are deduplicated, and neither bindings
nor layout resources contain secrets, customer/order metadata or private SVG
originals. Loading failure keeps an explicit retry state and releases the
selector's loading controls.

The host standing-quantity overlay uses public kernel scene bounds and the
viewer's SVG viewport transform, refreshing its anchors through the camera
callback (including resize). Compact controls sit inside the area when space
permits or immediately beside it. Only the generic standing detail controls are
replaced; the package still owns map rendering, hit testing and seat gestures.
Quantity edits remain drafts until explicit confirmation, with validation and
checkout updates owned by the existing adapter and form session. Selectable
standing areas suppress the duplicate product tooltip; unavailable areas retain
their explanation.

The pnpm patch `patches/venue-layout-hit-slop.patch` extends seat taps by eight
CSS pixels, independent of zoom. Direct kernel hits retain priority. Near misses
probe screen pixels in distance order against the unchanged kernel, preserving
rotations, groups, unavailable-seat barriers and atomic selection units. Standing
areas retain exact hit testing. The patch belongs to the shared renderer boundary;
the host does not duplicate geometry or reservation logic.

The expanded standing control names the area and shows unit price, availability,
a numeric stepper and a labeled confirmation action. Wheel gestures over the
control are relayed to the viewer SVG at their original cursor coordinates.
On narrow viewports it anchors above the area if the zoom toolbar would overlap.
Published Blueprint catalogs are checked against the canonical dictionaries by
the build gate; browser fixtures consume the actual public catalogs.

Interaction references: [Masters of Rock standing purchase](https://www.mastersofrock.cz/en/koncerty/2027-masters-of-rock)
uses ticket type, price and a minus/quantity/plus stepper;
[Rock am Ring](https://www.rock-am-ring.com/en/tickets) separates admission categories
from camping/add-ons. The map anchor is Festapp's adaptation for mixed seating
and standing plans, not a claim that those festivals use this exact overlay.

Standing controls are hidden until the area is activated. The non-modal mini
dialog opens beside that area, proposes one as an uncommitted draft for an empty
selection, and closes on confirmation, Escape or outside pointer/click. Dismissal
discards the unconfirmed draft; only explicit confirmation updates checkout.
Escape/confirmation restores focus to the area's semantic button. Outside clicks
continue normally and pending completion never steals their focus.
This follows the action-first initial offer seen in [Sziget's ticket shop](https://szigetfestival.com/en/tickets).
[Primavera Sound's AccessTicket shop](https://primavera-sound-barcelona-2027.webstore.acst.app/)
separates ticket-category selection from its Amount section; proceeding there
requires login, so its authenticated checkout was not evaluated.
