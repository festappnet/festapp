import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/legacy_map_surface.dart';
import 'package:fstapp/components/map/map_renderer_host.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:latlong2/latlong.dart';

void main() {
  MapSurfaceModel model({
    bool active = true,
    MapScene scene = const MapScene(),
  }) =>
      MapSurfaceModel(
        active: active,
        scene: scene,
        icons: const [],
        initialCenter: const LatLng(49.8, 18.2),
        initialZoom: 14,
        viewport: MapViewportCoordinator(),
        onMapTap: (_) {},
        onPlaceTap: (_) {},
      );

  LegacyMapConfiguration legacy() => LegacyMapConfiguration.online(MapLayer());

  test('web always resolves to the legacy Live View renderer', () {
    expect(
      MapRendererHost.resolveRenderer(
        configuredRenderer: OfflineMapRenderer.maplibre,
        isOffline: true,
        isWeb: true,
      ),
      OfflineMapRenderer.legacy,
    );
  });

  testWidgets('selects exactly the configured renderer', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.maplibre,
        isOffline: true,
        model: model(),
        legacy: legacy(),
        mapLibre: const MapLibreMapConfiguration(
          style: null,
          unavailable: Text('maplibre'),
        ),
      ),
    ));

    expect(find.text('maplibre'), findsOneWidget);
    expect(find.text('legacy'), findsNothing);
  });

  testWidgets('keeps the concrete surface warm while its tab is inactive',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: true,
        model: model(active: false),
        legacy: LegacyMapConfiguration.offlineUnavailable(MapLayer()),
      ),
    ));

    expect(find.byType(LegacyMapSurface), findsOneWidget);
    expect(find.byType(fm.FlutterMap), findsOneWidget);
  });

  testWidgets('keeps offline Legacy as an explicit supported renderer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: true,
        model: model(),
        legacy: LegacyMapConfiguration.offlineUnavailable(MapLayer()),
      ),
    ));

    expect(find.byType(LegacyMapSurface), findsOneWidget);
    final map = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
    expect(map.options.maxZoom, MapZoomLimits.interactionMaximum);
  });

  testWidgets('Legacy renders the location supplied by the shared map scene',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: true,
        model: model(
          scene: const MapScene(
            showCurrentLocation: true,
            currentLocation: LatLng(49.8, 18.2),
          ),
        ),
        legacy: LegacyMapConfiguration.offlineUnavailable(MapLayer()),
      ),
    ));

    const locationMarkerKey = Key('legacy-current-location-marker');
    expect(find.byKey(locationMarkerKey), findsOneWidget);
    final locationLayer = tester
        .widgetList<fm.MarkerLayer>(find.byType(fm.MarkerLayer))
        .singleWhere(
          (layer) => layer.markers.any(
            (marker) => marker.child.key == locationMarkerKey,
          ),
        );
    final locationMarker = locationLayer.markers.singleWhere(
      (marker) => marker.child.key == locationMarkerKey,
    );
    expect(locationMarker.width, 20);
    expect(locationMarker.height, 20);
  });

  testWidgets('Legacy hides a retained location while its scene is inactive',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: true,
        model: model(
          scene: const MapScene(
            currentLocation: LatLng(49.8, 18.2),
          ),
        ),
        legacy: LegacyMapConfiguration.offlineUnavailable(MapLayer()),
      ),
    ));

    expect(
      find.byKey(const Key('legacy-current-location-marker')),
      findsNothing,
    );
  });

  testWidgets('does not silently fall back when MapLibre is unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.maplibre,
        isOffline: true,
        model: model(),
        legacy: legacy(),
      ),
    ));

    expect(tester.takeException(), isStateError);
    expect(find.byType(LegacyMapSurface), findsNothing);
  });

  test('online maps resolve to the legacy Live View renderer', () {
    expect(
      MapRendererHost.resolveRenderer(
        configuredRenderer: OfflineMapRenderer.maplibre,
        isOffline: false,
        isWeb: false,
      ),
      OfflineMapRenderer.legacy,
    );
  });

  test('map renderers allow the maximum supported interaction zoom', () {
    expect(MapZoomLimits.interactionMaximum, 22);
  });

  testWidgets('online Legacy overzooms without requesting deeper raster tiles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: false,
        model: model(),
        legacy: legacy(),
      ),
    ));

    final map = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
    final tiles = tester.widget<fm.TileLayer>(find.byType(fm.TileLayer));
    expect(map.options.maxZoom, MapZoomLimits.interactionMaximum);
    expect(tiles.maxZoom, MapZoomLimits.interactionMaximum);
    expect(tiles.maxNativeZoom, MapZoomLimits.onlineRasterNativeMaximum);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('configured online provider uses one identified fallback layer',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: false,
        model: model(),
        legacy: LegacyMapConfiguration.online(
          MapLayer(layerLink: 'https://primary.example/{z}/{x}/{y}.png'),
        ),
      ),
    ));

    final layers = tester.widgetList<fm.TileLayer>(find.byType(fm.TileLayer));
    expect(layers, hasLength(1));
    expect(
        layers.single.urlTemplate, 'https://primary.example/{z}/{x}/{y}.png');
    expect(layers.single.fallbackUrl,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(
      (layers.single.tileProvider as fm.NetworkTileProvider)
          .attemptDecodeOfHttpErrorResponses,
      isFalse,
    );
    expect(
      layers.single.tileProvider.headers['User-Agent'],
      'Festapp/Flutter (+${AppConfig.supportUrl})',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Legacy place long press uses the shared navigation callback',
      (tester) async {
    const coordinate = LatLng(49.8, 18.2);
    int? longPressedPlaceId;
    final longPressModel = MapSurfaceModel(
      active: true,
      scene: MapScene(
        places: [
          MapPlacePresentation(
            place: MapPlaceModel(
              id: 7,
              title: 'WC',
              latLng: coordinate,
            ),
            coordinate: coordinate,
            pinColorValue: Colors.orange.toARGB32(),
          ),
        ],
      ),
      icons: const [],
      initialCenter: coordinate,
      initialZoom: 14,
      viewport: MapViewportCoordinator(),
      onMapTap: (_) {},
      onPlaceTap: (_) {},
      onPlaceLongPress: (placeId) => longPressedPlaceId = placeId,
    );

    await tester.pumpWidget(MaterialApp(
      home: MapRendererHost(
        renderer: OfflineMapRenderer.legacy,
        isOffline: false,
        model: longPressModel,
        legacy: legacy(),
      ),
    ));

    final longPressTarget = find.byWidgetPredicate(
      (widget) => widget is GestureDetector && widget.onLongPress != null,
    );
    expect(longPressTarget, findsOneWidget);
    await tester.longPress(longPressTarget);
    expect(longPressedPlaceId, 7);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });
}
