# Festapp patch for `maplibre_platform_interface` 0.3.6

This repository pin adds `StyleController.addImageWithPixelRatio`. Widget
rasters pass their physical-to-logical pixel ratio through this interface so
native adapters can preserve sharp pixels and the intended logical size.

It also adds `MapLibreMap.active`, allowing retained navigation tabs to keep a
warm native map while pausing its renderer and sensors when hidden.

The default implementation delegates to `addImage` for compatibility. Remove
this package and its root override once upstream exposes equivalent image-scale
metadata and a retained-map activity lifecycle across Android and iOS.
