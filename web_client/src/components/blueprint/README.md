# Blueprint public selection

`blueprint_selector.js` owns the dialog lifecycle and mounts the public `@festapp/venue-layout` renderer. `BlueprintLayoutAdapter` projects the canonical layout and public bindings into presentation and forwards selection to the existing form session. Standing quantities use the existing ticket product fields.

The package loads its unchanged kernel asset through `loadKernel`; `loadLayoutAssets` validates processed image metadata and bytes. The host does not render raw SVG or implement geometry, gestures or transforms. Closing aborts loading and disposes the shared mount. Missing canonical geometry is a repairable load error, never a legacy renderer fallback.

Financial operations, hold ownership, limits, products and order payloads remain in the form/session/server owners. Public presentation never includes administrator customer or order metadata.
