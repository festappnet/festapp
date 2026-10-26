# Festapp patch for `maplibre_platform_interface` 0.3.7

This repository pin adds `StyleController.addImageWithPixelRatio`. Widget
rasters pass their physical-to-logical pixel ratio through this interface so
native adapters can preserve sharp pixels and the intended logical size.

It also adds `MapLibreMap.active`, allowing retained navigation tabs to keep a
warm native map while pausing its renderer and sensors when hidden.

The default implementation delegates to `addImage` for compatibility. Remove
this package and its root override once upstream exposes equivalent image-scale
metadata and a retained-map activity lifecycle across Android and iOS.

## Upstream review: 0.3.7 (2026-10-25)

Rebased this adapter onto the published 0.3.7 archive while retaining the
patches described above. Upstream still lacks the pixel-ratio and retained-map
activity contracts. Android still needs the asynchronous style-loaded callback
and a fixed native renderer version; iOS still needs the public plugin header
and navigation-grade location policy. The dependency overrides remain required.
