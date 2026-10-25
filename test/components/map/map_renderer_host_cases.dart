import 'package:fstapp/widgets/dependency_material_bridge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/raster_map_surface.dart';
import 'package:fstapp/components/map/map_renderer_host.dart';
import 'package:fstapp/components/map/map_strings.dart';
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

  test('web always resolves to the online raster renderer', () {
    expect(
      MapRendererHost.resolveRenderer(
        isOffline: true,
        isWeb: true,
      ),
      MapRenderer.raster,
    );
  });

  testWidgets('native offline maps use MapLibre', (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: true,
        model: model(),
        onlineLayer: MapLayer(),
        mapLibre: const MapLibreMapConfiguration(
          style: null,
          unavailable: Text('maplibre'),
        ),
      ),
    ));

    expect(find.text('maplibre'), findsOneWidget);
    expect(find.byType(RasterMapSurface), findsNothing);
  });

  testWidgets('keeps the concrete surface warm while its tab is inactive',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(active: false),
        onlineLayer: MapLayer(),
      ),
    ));

    expect(find.byType(RasterMapSurface), findsOneWidget);
    expect(find.byType(fm.FlutterMap), findsOneWidget);
  });

  testWidgets('online raster supports the shared maximum zoom', (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(),
        onlineLayer: MapLayer(),
      ),
    ));

    expect(find.byType(RasterMapSurface), findsOneWidget);
    final map = tester.widget<fm.FlutterMap>(find.byType(fm.FlutterMap));
    expect(map.options.maxZoom, MapZoomLimits.interactionMaximum);
  });

  testWidgets('Raster renders the location supplied by the shared map scene',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(
          scene: const MapScene(
            showCurrentLocation: true,
            currentLocation: LatLng(49.8, 18.2),
          ),
        ),
        onlineLayer: MapLayer(),
      ),
    ));

    const locationMarkerKey = Key('raster-current-location-marker');
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

  testWidgets('Raster hides a retained location while its scene is inactive',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(
          scene: const MapScene(
            currentLocation: LatLng(49.8, 18.2),
          ),
        ),
        onlineLayer: MapLayer(),
      ),
    ));

    expect(
      find.byKey(const Key('raster-current-location-marker')),
      findsNothing,
    );
  });

  testWidgets('does not silently fall back when MapLibre is unavailable',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: true,
        model: model(),
        onlineLayer: MapLayer(),
      ),
    ));

    expect(tester.takeException(), isStateError);
    expect(find.byType(RasterMapSurface), findsNothing);
  });

  test('online maps resolve to the raster renderer', () {
    expect(
      MapRendererHost.resolveRenderer(
        isOffline: false,
        isWeb: false,
      ),
      MapRenderer.raster,
    );
  });

  test('map renderers allow the maximum supported interaction zoom', () {
    expect(MapZoomLimits.interactionMaximum, 22);
  });

  testWidgets('online raster overzooms without requesting deeper raster tiles',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(),
        onlineLayer: MapLayer(),
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

  testWidgets(
      'configured provider failure switches layer and attribution to OSM',
      (tester) async {
    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: model(),
        onlineLayer: MapLayer(
          layerLink: 'https://primary.example/{z}/{x}/{y}.png',
          text: 'Primary maps',
        ),
      ),
    ));

    var layers = tester.widgetList<fm.TileLayer>(find.byType(fm.TileLayer));
    expect(
        layers.single.urlTemplate, 'https://primary.example/{z}/{x}/{y}.png');
    expect(layers.single.fallbackUrl, isNull);
    expect(layers.single.errorTileCallback, isNotNull);
    expect(
      tester
          .widgetList<fm.TextSourceAttribution>(
              find.byType(fm.TextSourceAttribution))
          .map((attribution) => attribution.text),
      ['Primary maps'],
    );
    expect(
      (layers.single.tileProvider as fm.NetworkTileProvider)
          .attemptDecodeOfHttpErrorResponses,
      isFalse,
    );
    expect(
      layers.single.tileProvider.headers['User-Agent'],
      'Festapp/Flutter (+${AppConfig.supportUrl})',
    );

    layers.single.errorTileCallback!(
      _FakeTileImage(),
      StateError('HTTP 403'),
      null,
    );
    await tester.pump();

    layers = tester.widgetList<fm.TileLayer>(find.byType(fm.TileLayer));
    expect(layers.single.urlTemplate,
        'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(layers.single.errorTileCallback, isNull);
    expect(find.byType(fm.LogoSourceAttribution), findsNothing);
    expect(
      tester
          .widgetList<fm.TextSourceAttribution>(
              find.byType(fm.TextSourceAttribution))
          .map((attribution) => attribution.text),
      [MapStrings.openStreetMapAttribution],
    );

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('Raster place long press uses the shared navigation callback',
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

    await tester.pumpWidget(MaterialApp(builder: DependencyMaterialBridge.builder,
      home: MapRendererHost(
        isOffline: false,
        model: longPressModel,
        onlineLayer: MapLayer(),
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

class _FakeTileImage implements fm.TileImage {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
