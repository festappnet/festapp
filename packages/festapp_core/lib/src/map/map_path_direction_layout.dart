import 'dart:math' as math;

import 'package:festapp_core/map.dart';
import 'package:latlong2/latlong.dart';

/// Places a small, bounded set of filled direction triangles along routes.
///
/// The interface deliberately accepts only the route geometry. Vertex density,
/// geodesic interpolation, spacing and arrow sizing stay inside this module so
/// every renderer receives exactly the same direction geometry.
abstract final class MapPathDirectionLayout {
  static const _targetSpacingPixels = 120.0;
  static const _maximumTriangleCount = 12;
  static const _bodyPixels = 16.0;
  static const _endpointPaddingPixels = 1.0;
  static const _simplificationTolerancePixels = 0.75;
  static const _tileSize = 512.0;

  static List<MapDirectionPresentation> directions(
    List<MapPathPresentation> paths, {
    required double zoom,
  }) {
    final directions = <MapDirectionPresentation>[];
    for (final path in paths) {
      if (path.kind != MapPathKind.main) continue;
      final placements = _placements(path.points, zoom: zoom);
      for (var index = 0; index < placements.length; index++) {
        final placement = placements[index];
        directions.add(
          MapDirectionPresentation(
            id: '${path.id}_direction_$index',
            groupId: path.groupId,
            coordinate: placement.coordinate,
            bearingDegrees: placement.bearingDegrees,
            bodyPixels: _bodyPixels,
            colorValue: path.colorValue,
          ),
        );
      }
    }
    return directions;
  }

  static List<_DirectionPlacement> _placements(
    List<LatLng> route, {
    double zoom = 14,
  }) {
    final directionPoints = _simplifyProjected(
      route.map((point) => _project(point, zoom)).toList(growable: false),
    );
    final projectedSegments = List.generate(
      directionPoints.length > 1 ? directionPoints.length - 1 : 0,
      (index) => _ProjectedSegment.fromPoints(
        directionPoints[index],
        directionPoints[index + 1],
      ),
      growable: false,
    ).where((segment) => segment.lengthPixels > 0).toList(growable: false);
    if (projectedSegments.isEmpty) return const [];
    final screenLengthPixels = projectedSegments
        .map((segment) => segment.lengthPixels)
        .reduce((sum, length) => sum + length);
    final count = math.min(
      _maximumTriangleCount,
      math.max(1, (screenLengthPixels / _targetSpacingPixels).ceil()),
    );
    final usableSegments = projectedSegments
        .where(
          (segment) =>
              segment.lengthPixels > _bodyPixels + 2 * _endpointPaddingPixels,
        )
        .toList(growable: false);
    if (usableSegments.isEmpty) return const [];
    final totalUsablePixels = usableSegments
        .map((segment) => segment.usablePixels)
        .reduce((sum, length) => sum + length);
    final usableInterval = totalUsablePixels / (count + 1);

    return List.generate(count, (index) {
      final targetPixels = usableInterval * (index + 1);
      var precedingPixels = 0.0;
      var segment = usableSegments.last;
      for (final candidate in usableSegments) {
        if (targetPixels <= precedingPixels + candidate.usablePixels) {
          segment = candidate;
          break;
        }
        precedingPixels += candidate.usablePixels;
      }
      final centerPixels =
          _bodyPixels / 2 +
          _endpointPaddingPixels +
          (targetPixels - precedingPixels).clamp(0, segment.usablePixels);
      final center = _WorldPoint(
        segment.start.x + segment.unitX * centerPixels,
        segment.start.y + segment.unitY * centerPixels,
      );
      final bearingDegrees =
          math.atan2(segment.unitX, -segment.unitY) * 180 / math.pi;
      return _DirectionPlacement(
        coordinate: _unproject(center, zoom),
        bearingDegrees: bearingDegrees,
      );
    }, growable: false);
  }

  static _WorldPoint _project(LatLng point, double zoom) {
    final worldPixels = _tileSize * math.pow(2, zoom.clamp(0, 22));
    final latitude = point.latitude.clamp(-85.05112878, 85.05112878);
    final sinLatitude = math.sin(latitude * math.pi / 180);
    return _WorldPoint(
      (point.longitude + 180) / 360 * worldPixels,
      (0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi)) *
          worldPixels,
    );
  }

  static LatLng _unproject(_WorldPoint point, double zoom) {
    final worldPixels = _tileSize * math.pow(2, zoom.clamp(0, 22));
    final longitude = point.x / worldPixels * 360 - 180;
    final mercatorY = math.pi - 2 * math.pi * point.y / worldPixels;
    final hyperbolicSine = (math.exp(mercatorY) - math.exp(-mercatorY)) / 2;
    final latitude = math.atan(hyperbolicSine) * 180 / math.pi;
    return LatLng(latitude, longitude);
  }

  static List<_WorldPoint> _simplifyProjected(List<_WorldPoint> points) {
    if (points.length <= 2) return points;
    final keep = List<bool>.filled(points.length, false)
      ..first = true
      ..last = true;
    final ranges = <_PointRange>[_PointRange(0, points.length - 1)];
    while (ranges.isNotEmpty) {
      final range = ranges.removeLast();
      var furthestIndex = -1;
      var furthestDistance = 0.0;
      for (var index = range.start + 1; index < range.end; index++) {
        final distance = _distanceToSegment(
          points[index],
          points[range.start],
          points[range.end],
        );
        if (distance > furthestDistance) {
          furthestDistance = distance;
          furthestIndex = index;
        }
      }
      if (furthestIndex < 0 ||
          furthestDistance <= _simplificationTolerancePixels) {
        continue;
      }
      keep[furthestIndex] = true;
      ranges
        ..add(_PointRange(range.start, furthestIndex))
        ..add(_PointRange(furthestIndex, range.end));
    }
    return [
      for (var index = 0; index < points.length; index++)
        if (keep[index]) points[index],
    ];
  }

  static double _distanceToSegment(
    _WorldPoint point,
    _WorldPoint start,
    _WorldPoint end,
  ) {
    final deltaX = end.x - start.x;
    final deltaY = end.y - start.y;
    final squaredLength = deltaX * deltaX + deltaY * deltaY;
    if (squaredLength == 0) {
      return math.sqrt(
        math.pow(point.x - start.x, 2) + math.pow(point.y - start.y, 2),
      );
    }
    final fraction =
        (((point.x - start.x) * deltaX + (point.y - start.y) * deltaY) /
                squaredLength)
            .clamp(0, 1);
    final nearestX = start.x + fraction * deltaX;
    final nearestY = start.y + fraction * deltaY;
    return math.sqrt(
      math.pow(point.x - nearestX, 2) + math.pow(point.y - nearestY, 2),
    );
  }
}

final class _WorldPoint {
  final double x;
  final double y;

  const _WorldPoint(this.x, this.y);
}

final class _ProjectedSegment {
  final _WorldPoint start;
  final double lengthPixels;
  final double unitX;
  final double unitY;

  const _ProjectedSegment({
    required this.start,
    required this.lengthPixels,
    required this.unitX,
    required this.unitY,
  });

  double get usablePixels =>
      lengthPixels -
      MapPathDirectionLayout._bodyPixels -
      2 * MapPathDirectionLayout._endpointPaddingPixels;

  factory _ProjectedSegment.fromPoints(_WorldPoint start, _WorldPoint end) {
    final deltaX = end.x - start.x;
    final deltaY = end.y - start.y;
    final length = math.sqrt(deltaX * deltaX + deltaY * deltaY);
    return _ProjectedSegment(
      start: start,
      lengthPixels: length,
      unitX: length == 0 ? 0 : deltaX / length,
      unitY: length == 0 ? 0 : deltaY / length,
    );
  }
}

final class _PointRange {
  final int start;
  final int end;

  const _PointRange(this.start, this.end);
}

final class _DirectionPlacement {
  final LatLng coordinate;
  final double bearingDegrees;

  const _DirectionPlacement({
    required this.coordinate,
    required this.bearingDegrees,
  });
}
