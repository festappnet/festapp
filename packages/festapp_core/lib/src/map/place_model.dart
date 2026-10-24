import 'package:festapp_core/json_values.dart';

const _unchanged = Object();

class PlaceModel {
  static const String aggregateVersionColumn = 'aggregate_version';

  /// Raw `{"lat": .., "lng": ..}` map (may be null). It is stored unwrapped:
  /// [fromJson] reads `coordinates["latLng"]`, the app grid adapter reads the cell
  /// value directly, and [toJson] wraps it back into `{"latLng": ...}`.
  /// Do not change one side without the other. Use [hasCoordinates] before
  /// calling [getLat]/[getLng] — a place may legitimately have no coordinates.
  final dynamic latLng;
  final int? id;
  final String? title;
  final String? description;
  final String? type;
  final int? order;
  final int? icon;
  final int aggregateVersion;
  final bool isHidden;

  static const String WithoutValue = "---";
  static const String groupType = 'group';
  static const String coordinatesLatLngKey = 'latLng';
  static const String latitudeKey = 'lat';
  static const String longitudeKey = 'lng';

  static const String placesOffline = "places";
  static const String placeObjectColumn = "placeObject";

  double getLat() => latLng[latitudeKey];
  double getLng() => latLng[longitudeKey];

  /// Whether this place has usable map coordinates. A place without them must
  /// be filtered out before building a map marker (which force-reads lat/lng).
  bool get hasCoordinates =>
      latLng != null &&
      latLng?[latitudeKey] != null &&
      latLng?[longitudeKey] != null;

  /// A hidden `group` place is an implementation-owned point created solely
  /// for one group. Visible catalog places are shared references and must never
  /// be updated or deleted as a side effect of editing that group.
  bool get isPrivateGroupLocation => type == groupType && isHidden;

  factory PlaceModel.fromJson(Map<String, dynamic> json) {
    return PlaceModel(
      latLng: json.containsKey('coordinates')
          ? json['coordinates'][coordinatesLatLngKey]
          : null,
      id: json['id'],
      title: json.containsKey('title') ? json['title'] : null,
      description: json.containsKey('description') ? json['description'] : null,
      type: json.containsKey('type') ? json['type'] : null,
      isHidden: json.containsKey('is_hidden') ? json['is_hidden'] : false,
      order: json['order'],
      icon: json['icon'],
      aggregateVersion: (json['aggregate_version'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'coordinates': {coordinatesLatLngKey: latLng},
    'description': description,
    'type': type,
    'is_hidden': isHidden,
    'order': order,
    'icon': icon,
  };

  PlaceModel({
    dynamic latLng,
    this.id,
    this.title,
    this.description,
    this.type,
    this.order,
    this.icon,
    this.aggregateVersion = 0,
    this.isHidden = false,
  }) : latLng = freezeJsonValue(latLng);

  String toBasicString() => title.toString();
  PlaceModel copyWith({
    Object? latLng = _unchanged,
    Object? id = _unchanged,
    Object? title = _unchanged,
    Object? description = _unchanged,
    Object? type = _unchanged,
    Object? order = _unchanged,
    Object? icon = _unchanged,
    Object? aggregateVersion = _unchanged,
    Object? isHidden = _unchanged,
  }) => PlaceModel(
    latLng: identical(latLng, _unchanged) ? this.latLng : latLng,
    id: identical(id, _unchanged) ? this.id : id as int?,
    title: identical(title, _unchanged) ? this.title : title as String?,
    description: identical(description, _unchanged)
        ? this.description
        : description as String?,
    type: identical(type, _unchanged) ? this.type : type as String?,
    order: identical(order, _unchanged) ? this.order : order as int?,
    icon: identical(icon, _unchanged) ? this.icon : icon as int?,
    aggregateVersion: identical(aggregateVersion, _unchanged)
        ? this.aggregateVersion
        : aggregateVersion as int,
    isHidden: identical(isHidden, _unchanged)
        ? this.isHidden
        : isHidden as bool,
  );
}
