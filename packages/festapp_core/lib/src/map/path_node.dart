import 'map_coordinate.dart';

/// A single vertex of a path segment. It is either:
/// - a reference to an existing place (`placeId`), serialized as a bare number
///   (the legacy format, backward compatible), or
/// - a free point with inline coordinates, serialized as `{"lat":..,"lng":..}`.
///
/// Free points never become rows in the `places` table — they live only inside
/// `path_groups.path_data`.
class PathNode {
  final int? placeId;
  final double? lat;
  final double? lng;

  const PathNode._({this.placeId, this.lat, this.lng});

  /// Reference to an existing place by its id.
  factory PathNode.place(int id) => PathNode._(placeId: id);

  /// A free coordinate that is not backed by a place row.
  factory PathNode.point(double lat, double lng) =>
      PathNode._(lat: lat, lng: lng);

  bool get isPoint => placeId == null;

  /// Parse a single JSON node: a number is a place reference, a map is a free
  /// point. Returns null for anything unrecognized.
  static PathNode? fromJson(dynamic raw) {
    if (raw is int) return PathNode.place(raw);
    if (raw is num) return PathNode.place(raw.toInt());
    if (raw is Map) {
      final lat = raw['lat'];
      final lng = raw['lng'];
      if (lat is num && lng is num) {
        return PathNode.point(lat.toDouble(), lng.toDouble());
      }
    }
    return null;
  }

  /// Serialize back to either an `int` (place ref) or a `{lat,lng}` map.
  dynamic toJson() => isPoint ? {'lat': lat, 'lng': lng} : placeId;

  /// Resolve this node to a map coordinate. Place refs are looked up in
  /// [resolvePlace]; free points return their inline coordinate. Returns null when a
  /// referenced place cannot be found.
  MapCoordinate? resolve(MapCoordinate? Function(int placeId) resolvePlace) {
    if (isPoint) return MapCoordinate(lat!, lng!);
    return resolvePlace(placeId!);
  }

  @override
  bool operator ==(Object other) =>
      other is PathNode &&
      other.placeId == placeId &&
      other.lat == lat &&
      other.lng == lng;

  @override
  int get hashCode => Object.hash(placeId, lat, lng);

  @override
  String toString() => isPoint ? '@$lat:$lng' : '$placeId';
}
