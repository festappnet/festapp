import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/maplibre/maplibre_scene_controller.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('fallback place pin is smaller than a custom place pin', () {
    expect(MapLibreSceneController.fallbackPlaceIconSize, 36);
    expect(MapLibreSceneController.fallbackPlaceIconSize, lessThan(52));
  });

  test('place edit lifecycle preserves and then clears the original position',
      () {
    final place = MapPlacePresentation(
      place: MapPlaceModel(
        id: 393,
        title: 'Kostel svatého Václava',
        latLng: const LatLng(49.8357, 18.2948),
      ),
      coordinate: const LatLng(49.8357, 18.2948),
      pinColorValue: 0xff00aa55,
    );

    final editing = place.startEditing().moveTo(const LatLng(49.8360, 18.2950));
    expect(editing.originalCoordinate, place.coordinate);
    expect(editing.isEditing, isTrue);

    final saved = editing.finishEditing();
    expect(saved.coordinate, editing.coordinate);
    expect(saved.originalCoordinate, isNull);
    expect(saved.isEditing, isFalse);
  });

  test('serializes places with stable hit-test identity and presentation', () {
    final json = jsonDecode(MapLibreSceneController.placesGeoJson([
      MapPlacePresentation(
        place: MapPlaceModel(
          id: 393,
          title: 'Kostel svatého Václava',
          latLng: const LatLng(49.8357, 18.2948),
          icon: 17,
        ),
        coordinate: const LatLng(49.8357, 18.2948),
        pinColorValue: 0xff00aa55,
        showTitle: true,
        isFocused: true,
      ),
    ])) as Map<String, dynamic>;

    final feature = (json['features'] as List).single as Map<String, dynamic>;
    expect(feature['id'], 393);
    expect(feature['properties']['place_id'], 393);
    expect(feature['properties']['label'], 'Kostel svatého Václava');
    expect(feature['properties']['icon_key'], 'place-17-ff00aa55');
    expect(feature['properties']['z_index'], 1);
    expect(feature['geometry']['coordinates'], [18.2948, 49.8357]);
  });

  test('serializes renderer-neutral paths as native line features', () {
    final json = jsonDecode(MapLibreSceneController.pathsGeoJson([
      MapPathPresentation(
        id: 'group_16_0',
        groupId: 16,
        points: const [LatLng(49.82, 18.26), LatLng(49.83, 18.27)],
        colorValue: 0xffff3366,
        strokeWidth: 3,
        kind: MapPathKind.main,
      ),
    ])) as Map<String, dynamic>;

    final feature = (json['features'] as List).single as Map<String, dynamic>;
    expect(feature['properties']['group_id'], 16);
    expect(feature['properties']['kind'], 'main');
    expect(feature['properties']['color'], '#ff3366ff');
    expect(feature['geometry']['type'], 'LineString');
  });

  test('serializes direction markers as rotated screen-space symbols', () {
    final json = jsonDecode(MapLibreSceneController.directionsGeoJson([
      MapDirectionPresentation(
        id: 'direction_0',
        groupId: 16,
        coordinate: const LatLng(49.821, 18.262),
        bearingDegrees: 72,
        bodyPixels: 16,
        colorValue: 0xffff3366,
      ),
    ])) as Map<String, dynamic>;

    final feature = (json['features'] as List).single as Map<String, dynamic>;
    expect(feature['geometry']['type'], 'Point');
    expect(feature['properties']['group_id'], 16);
    expect(feature['properties']['bearing'], 72);
    expect(feature['properties']['icon_key'], contains('direction-'));
    expect(feature['geometry']['coordinates'], [18.262, 49.821]);
  });

  test('serializes free draw points for the native circle layer', () {
    final json = jsonDecode(MapLibreSceneController.drawPointsGeoJson(const [
      MapDrawPointPresentation(
        coordinate: LatLng(49.82, 18.26),
        colorValue: 0xff0066cc,
      ),
    ])) as Map<String, dynamic>;

    final feature = (json['features'] as List).single as Map<String, dynamic>;
    expect(feature['properties']['color'], '#0066ccff');
    expect(feature['geometry']['coordinates'], [18.26, 49.82]);
  });
}
