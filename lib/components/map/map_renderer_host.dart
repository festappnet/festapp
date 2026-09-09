import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/legacy_map_surface.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/maplibre/maplibre_map_surface.dart';
import 'package:fstapp/components/map/offline_map_bundle_manager.dart';
import 'package:fstapp/components/map/offline_map_configuration.dart';

export 'package:fstapp/components/map/map_surface_model.dart';

class LegacyMapConfiguration {
  final bool offline;
  final MapLayer layer;
  final LegacyMapResources? resources;
  final String? sourceName;

  const LegacyMapConfiguration._({
    required this.offline,
    required this.layer,
    this.resources,
    this.sourceName,
  });

  factory LegacyMapConfiguration.online(MapLayer layer) =>
      LegacyMapConfiguration._(offline: false, layer: layer);

  factory LegacyMapConfiguration.offlineUnavailable(MapLayer layer) =>
      LegacyMapConfiguration._(offline: true, layer: layer);

  static Future<LegacyMapConfiguration> openOffline({
    required MapLayer layer,
    required LegacyOfflineMapContract contract,
    required String mbtilesPath,
  }) async {
    final resources = await LegacyMapResources.open(
      styleUri: contract.styleUrl,
      mbtilesPath: mbtilesPath,
    );
    return LegacyMapConfiguration._(
      offline: true,
      layer: layer,
      resources: resources,
      sourceName: contract.sourceName,
    );
  }

  static Future<LegacyMapConfiguration> openOfflineBundle({
    required MapLayer layer,
    required LegacyOfflineMapContract contract,
    required OfflineMapBundleInstallation installation,
  }) async {
    final resources = await LegacyMapResources.openBundle(installation);
    return LegacyMapConfiguration._(
      offline: true,
      layer: layer,
      resources: resources,
      sourceName: contract.sourceName,
    );
  }

  void dispose() => resources?.dispose();
}

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
  final OfflineMapRenderer renderer;
  final bool isOffline;
  final MapSurfaceModel model;
  final LegacyMapConfiguration legacy;
  final MapLibreMapConfiguration? mapLibre;

  const MapRendererHost({
    required this.renderer,
    required this.isOffline,
    required this.model,
    required this.legacy,
    this.mapLibre,
    super.key,
  });

  static OfflineMapRenderer resolveRenderer({
    required OfflineMapRenderer configuredRenderer,
    required bool isOffline,
    required bool isWeb,
  }) =>
      isWeb || !isOffline ? OfflineMapRenderer.legacy : configuredRenderer;

  OfflineMapRenderer get effectiveRenderer => resolveRenderer(
        configuredRenderer: renderer,
        isOffline: isOffline,
        isWeb: kIsWeb,
      );

  @override
  Widget build(BuildContext context) {
    return switch (effectiveRenderer) {
      OfflineMapRenderer.legacy => LegacyMapSurface(
          offline: legacy.offline,
          layer: legacy.layer,
          model: model,
          offlineResources: legacy.resources,
          offlineSourceName: legacy.sourceName,
        ),
      OfflineMapRenderer.maplibre => _buildMapLibre(),
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
