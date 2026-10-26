import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/raster_map_surface.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/maplibre/maplibre_map_surface.dart';

export 'package:fstapp/components/map/map_surface_model.dart';

enum MapRenderer { raster, maplibre }

class MapLibreMapConfiguration {
  final String? style;
  final Widget unavailable;
  final int surfaceGeneration;
  final VoidCallback? onStyleLoadTimeout;
  final VoidCallback? onStyleLoadSuccess;

  const MapLibreMapConfiguration({
    required this.style,
    required this.unavailable,
    this.surfaceGeneration = 0,
    this.onStyleLoadTimeout,
    this.onStyleLoadSuccess,
  });
}

/// Canonical owner of renderer selection and surface construction.
class MapRendererHost extends StatelessWidget {
  final bool isOffline;
  final MapSurfaceModel model;
  final MapLayer onlineLayer;
  final MapLibreMapConfiguration? mapLibre;

  const MapRendererHost({
    required this.isOffline,
    required this.model,
    required this.onlineLayer,
    this.mapLibre,
    super.key,
  });

  static MapRenderer resolveRenderer({
    required bool isOffline,
    required bool isWeb,
  }) =>
      isWeb || !isOffline ? MapRenderer.raster : MapRenderer.maplibre;

  MapRenderer get effectiveRenderer => resolveRenderer(
        isOffline: isOffline,
        isWeb: kIsWeb,
      );

  @override
  Widget build(BuildContext context) {
    return switch (effectiveRenderer) {
      MapRenderer.raster => RasterMapSurface(
          layer: onlineLayer,
          model: model,
        ),
      MapRenderer.maplibre => _buildMapLibre(),
    };
  }

  Widget _buildMapLibre() {
    final configuration = mapLibre ??
        (throw StateError(
          'MapLibre was selected but its configuration is unavailable.',
        ));
    final style = configuration.style;
    if (style == null) return configuration.unavailable;
    return MapLibreMapSurface(
      key: ValueKey(configuration.surfaceGeneration),
      style: style,
      model: model,
      onStyleLoadTimeout: configuration.onStyleLoadTimeout,
      onStyleLoadSuccess: configuration.onStyleLoadSuccess,
    );
  }
}
