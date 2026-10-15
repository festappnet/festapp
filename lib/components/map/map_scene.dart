import 'package:festapp_core/map.dart';
import 'package:latlong2/latlong.dart';
import 'package:fstapp/components/map/map_place_model.dart';

const _unchangedCoordinate = Object();

class MapPlacePresentation {
  final MapPlaceModel place;
  final LatLng coordinate;
  final int pinColorValue;
  final bool showTitle;
  final bool isFocused;
  final bool isEditing;
  final LatLng? originalCoordinate;

  const MapPlacePresentation({
    required this.place,
    required this.coordinate,
    required this.pinColorValue,
    this.showTitle = false,
    this.isFocused = false,
    this.isEditing = false,
    this.originalCoordinate,
  });

  int get placeId => place.id!;
  String get title => place.title;
  LatLng get point => coordinate;
  LatLng? get oldPoint => originalCoordinate;
  String get iconKey {
    final identity = place.icon ?? place.type ?? 'default';
    return 'place-$identity-${pinColorValue.toRadixString(16)}';
  }

  MapPlacePresentation copyWith({
    LatLng? coordinate,
    int? pinColorValue,
    bool? showTitle,
    bool? isFocused,
    bool? isEditing,
    Object? originalCoordinate = _unchangedCoordinate,
  }) =>
      MapPlacePresentation(
        place: place,
        coordinate: coordinate ?? this.coordinate,
        pinColorValue: pinColorValue ?? this.pinColorValue,
        showTitle: showTitle ?? this.showTitle,
        isFocused: isFocused ?? this.isFocused,
        isEditing: isEditing ?? this.isEditing,
        originalCoordinate: identical(originalCoordinate, _unchangedCoordinate)
            ? this.originalCoordinate
            : originalCoordinate as LatLng?,
      );

  MapPlacePresentation startEditing() => copyWith(
        isEditing: true,
        originalCoordinate: coordinate,
      );

  MapPlacePresentation moveTo(LatLng point) => copyWith(coordinate: point);

  MapPlacePresentation finishEditing() => copyWith(
        isEditing: false,
        isFocused: false,
        showTitle: false,
        originalCoordinate: null,
      );

  MapPlacePresentation withFocus(bool focused) => copyWith(
        isFocused: focused,
        showTitle: focused,
      );
}

class MapDrawPointPresentation {
  final LatLng coordinate;
  final int colorValue;

  const MapDrawPointPresentation({
    required this.coordinate,
    required this.colorValue,
  });
}

class MapScene {
  final List<MapPlacePresentation> places;
  final List<MapPathPresentation> paths;
  final List<MapDirectionPresentation> directions;
  final List<MapDrawPointPresentation> drawPoints;
  final bool showCurrentLocation;
  final LatLng? currentLocation;

  const MapScene({
    this.places = const [],
    this.paths = const [],
    this.directions = const [],
    this.drawPoints = const [],
    this.showCurrentLocation = false,
    this.currentLocation,
  });
}
