import 'package:festapp_core/map.dart';
import 'dart:convert';

import 'package:fstapp/components/map/map_scene.dart';
import 'package:maplibre/maplibre.dart';

class MapLibreSceneController {
  static const fallbackPlaceIconSize = 36.0;
  static const placeSourceId = 'festapp-places-source';
  static const placeLayerId = 'festapp-places-layer';
  static const pathSourceId = 'festapp-paths-source';
  static const pathLayerId = 'festapp-paths-layer';
  static const directionSourceId = 'festapp-directions-source';
  static const directionLayerId = 'festapp-directions-layer';
  static const drawPointSourceId = 'festapp-draw-points-source';
  static const drawPointLayerId = 'festapp-draw-points-layer';

  final StyleController style;
  bool _registered = false;

  MapLibreSceneController(this.style);

  Future<void> register(MapScene scene) async {
    if (_registered) {
      await update(scene);
      return;
    }
    await style.addSource(GeoJsonSource(
      id: pathSourceId,
      data: pathsGeoJson(scene.paths),
    ));
    await style.addLayer(const LineStyleLayer(
      id: pathLayerId,
      sourceId: pathSourceId,
      paint: {
        'line-color': ['get', 'color'],
        'line-width': ['get', 'width'],
        'line-opacity': 1,
      },
    ));
    await style.addSource(GeoJsonSource(
      id: directionSourceId,
      data: directionsGeoJson(scene.directions),
    ));
    await style.addLayer(const SymbolStyleLayer(
      id: directionLayerId,
      sourceId: directionSourceId,
      layout: {
        'icon-image': ['get', 'icon_key'],
        'icon-size': 1,
        'icon-rotate': ['get', 'bearing'],
        'icon-rotation-alignment': 'map',
        'icon-allow-overlap': true,
      },
    ));
    await style.addSource(GeoJsonSource(
      id: placeSourceId,
      data: placesGeoJson(scene.places),
    ));
    await style.addLayer(const SymbolStyleLayer(
      id: placeLayerId,
      sourceId: placeSourceId,
      layout: {
        'icon-image': ['get', 'icon_key'],
        'icon-size': 1,
        'icon-anchor': 'bottom',
        'icon-allow-overlap': true,
        'text-field': ['get', 'label'],
        'text-font': ['noto_sans_bold'],
        'text-size': 13,
        'text-offset': [0, -3.8],
        'text-anchor': 'bottom',
        'text-justify': 'center',
        'text-max-width': 18,
        'text-padding': 4,
        'text-allow-overlap': true,
        'text-ignore-placement': true,
        'symbol-sort-key': ['get', 'z_index'],
      },
      paint: {
        'text-color': '#111111',
        'text-halo-color': '#FFFFFF',
        'text-halo-width': 3,
        'text-halo-blur': 0.5,
      },
    ));
    await style.addSource(GeoJsonSource(
      id: drawPointSourceId,
      data: drawPointsGeoJson(scene.drawPoints),
    ));
    await style.addLayer(const CircleStyleLayer(
      id: drawPointLayerId,
      sourceId: drawPointSourceId,
      paint: {
        'circle-radius': 7,
        'circle-color': ['get', 'color'],
        'circle-stroke-width': 2,
        'circle-stroke-color': '#ffffff',
      },
    ));
    _registered = true;
  }

  Future<void> update(MapScene scene) async {
    if (!_registered) {
      await register(scene);
      return;
    }
    await Future.wait([
      style.updateGeoJsonSource(
        id: placeSourceId,
        data: placesGeoJson(scene.places),
      ),
      style.updateGeoJsonSource(
        id: pathSourceId,
        data: pathsGeoJson(scene.paths),
      ),
      style.updateGeoJsonSource(
        id: directionSourceId,
        data: directionsGeoJson(scene.directions),
      ),
      style.updateGeoJsonSource(
        id: drawPointSourceId,
        data: drawPointsGeoJson(scene.drawPoints),
      ),
    ]);
  }

  static String placesGeoJson(List<MapPlacePresentation> places) => jsonEncode({
        'type': 'FeatureCollection',
        'features': places
            .map((place) => {
                  'type': 'Feature',
                  'id': place.placeId,
                  'properties': {
                    'place_id': place.placeId,
                    'title': place.title,
                    'label': place.showTitle ? place.title : '',
                    'icon_key': place.iconKey,
                    'pin_color': _hexColor(place.pinColorValue),
                    'z_index': place.isEditing
                        ? 2
                        : place.isFocused
                            ? 1
                            : 0,
                  },
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [
                      place.coordinate.longitude,
                      place.coordinate.latitude,
                    ],
                  },
                })
            .toList(growable: false),
      });

  static String pathsGeoJson(List<MapPathPresentation> paths) => jsonEncode({
        'type': 'FeatureCollection',
        'features': paths
            .map((path) => {
                  'type': 'Feature',
                  'id': path.id,
                  'properties': {
                    'group_id': path.groupId,
                    'kind': path.kind.name,
                    'color': _hexColor(path.colorValue),
                    'width': path.strokeWidth,
                  },
                  'geometry': {
                    'type': 'LineString',
                    'coordinates': path.points
                        .map((point) => [
                              point.longitude,
                              point.latitude,
                            ])
                        .toList(growable: false),
                  },
                })
            .toList(growable: false),
      });

  static String directionsGeoJson(
    List<MapDirectionPresentation> directions,
  ) =>
      jsonEncode({
        'type': 'FeatureCollection',
        'features': directions
            .map((direction) => {
                  'type': 'Feature',
                  'id': direction.id,
                  'properties': {
                    'group_id': direction.groupId,
                    'color': _hexColor(direction.colorValue),
                    'icon_key': direction.iconKey,
                    'bearing': direction.bearingDegrees,
                  },
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [
                      direction.coordinate.longitude,
                      direction.coordinate.latitude,
                    ],
                  },
                })
            .toList(growable: false),
      });

  static String drawPointsGeoJson(List<MapDrawPointPresentation> points) =>
      jsonEncode({
        'type': 'FeatureCollection',
        'features': points
            .asMap()
            .entries
            .map((entry) => {
                  'type': 'Feature',
                  'id': 'draw_${entry.key}',
                  'properties': {
                    'color': _hexColor(entry.value.colorValue),
                  },
                  'geometry': {
                    'type': 'Point',
                    'coordinates': [
                      entry.value.coordinate.longitude,
                      entry.value.coordinate.latitude,
                    ],
                  },
                })
            .toList(growable: false),
      });

  static String _hexColor(int color) {
    final alpha = (color >> 24) & 0xff;
    final red = (color >> 16) & 0xff;
    final green = (color >> 8) & 0xff;
    final blue = color & 0xff;
    String byte(int value) => value.toRadixString(16).padLeft(2, '0');
    return '#${byte(red)}${byte(green)}${byte(blue)}${byte(alpha)}';
  }
}
