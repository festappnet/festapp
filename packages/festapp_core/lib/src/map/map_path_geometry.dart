import 'package:latlong2/latlong.dart';

/// Semantic role of line geometry shared by every map renderer.
enum MapPathKind { main, draw }

/// Renderer-neutral line geometry. Rendering packages adapt this at the
/// surface boundary; feature and page state never stores package polylines.
class MapPathPresentation {
  final String id;
  final int? groupId;
  final List<LatLng> points;
  final int colorValue;
  final double strokeWidth;
  final MapPathKind kind;

  MapPathPresentation({
    required this.id,
    required List<LatLng> points,
    required this.colorValue,
    required this.strokeWidth,
    required this.kind,
    this.groupId,
  }) : points = List.unmodifiable(points),
       assert(points.length >= 2);
}

/// Renderer-neutral filled direction marker placed on a route.
class MapDirectionPresentation {
  final String id;
  final int? groupId;
  final LatLng coordinate;
  final double bearingDegrees;
  final double bodyPixels;
  final int colorValue;

  MapDirectionPresentation({
    required this.id,
    required this.coordinate,
    required this.bearingDegrees,
    required this.bodyPixels,
    required this.colorValue,
    this.groupId,
  });

  String get iconKey =>
      'direction-${colorValue.toRadixString(16)}-${bodyPixels.toStringAsFixed(1)}';
}
