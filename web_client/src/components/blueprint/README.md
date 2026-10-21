# Blueprint public selection

`blueprint_selector.js` owns the dialog lifecycle and mounts the public `@festapp/venue-layout` renderer. `BlueprintLayoutAdapter` projects the canonical layout and public bindings into presentation and forwards selection to the existing form session. Standing quantities use the existing ticket product fields.

The package loads its unchanged kernel asset through `loadKernel`; `loadLayoutAssets` validates processed image metadata and bytes. The host does not render raw SVG or implement geometry, gestures or transforms. Closing aborts loading and disposes the shared mount. Missing canonical geometry is a repairable load error, never a legacy renderer fallback.

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
