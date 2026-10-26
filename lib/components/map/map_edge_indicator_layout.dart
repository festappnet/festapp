import 'dart:math' as math;

import 'package:flutter/widgets.dart';

final class MapEdgeIndicatorPlacement {
  final Offset center;
  final Offset edgeTip;
  final double rotationRadians;

  const MapEdgeIndicatorPlacement({
    required this.center,
    required this.edgeTip,
    required this.rotationRadians,
  });
}

/// Renderer-neutral geometry for projecting an off-screen target onto the
/// usable map boundary defined by edge-adjacent controls.
abstract final class MapEdgeIndicatorLayout {
  static MapEdgeIndicatorPlacement? resolve({
    required Offset target,
    required Size viewport,
    List<Rect> occupiedRects = const [],
    double indicatorTipLength = 24,
    double indicatorClearance = 24,
  }) {
    if (!target.dx.isFinite || !target.dy.isFinite || viewport.isEmpty) {
      return null;
    }
    final viewportRect = Offset.zero & viewport;
    final usableRect = _usableRect(
      viewportRect,
      occupiedRects,
      indicatorClearance,
    );
    if (usableRect.width <= 0 || usableRect.height <= 0) return null;
    if (usableRect.contains(target)) return null;

    final origin = usableRect.center;
    final vector = target - origin;
    if (vector.distanceSquared == 0) return null;
    final edgeTip = _rayIntersection(origin, vector, usableRect);
    if (edgeTip == null) return null;
    final center = edgeTip - vector / vector.distance * indicatorTipLength;

    // The drop points down at zero rotation.
    final rotation = math.atan2(vector.dy, vector.dx) - math.pi / 2;
    return MapEdgeIndicatorPlacement(
      center: center,
      edgeTip: edgeTip,
      rotationRadians: rotation,
    );
  }

  static Rect _usableRect(
    Rect viewport,
    List<Rect> occupiedRects,
    double clearance,
  ) {
    var left = viewport.left;
    var top = viewport.top;
    var right = viewport.right;
    var bottom = viewport.bottom;

    for (final rect in occupiedRects) {
      final edges = <_EdgeInset>[];
      if (rect.left - viewport.left <= clearance) {
        edges.add(
          _EdgeInset(_EdgeSide.left, rect.right, rect.right * viewport.height),
        );
      }
      if (rect.top - viewport.top <= clearance) {
        edges.add(
          _EdgeInset(_EdgeSide.top, rect.bottom, rect.bottom * viewport.width),
        );
      }
      if (viewport.right - rect.right <= clearance) {
        edges.add(_EdgeInset(
          _EdgeSide.right,
          rect.left,
          (viewport.right - rect.left) * viewport.height,
        ));
      }
      if (viewport.bottom - rect.bottom <= clearance) {
        edges.add(_EdgeInset(
          _EdgeSide.bottom,
          rect.top,
          (viewport.bottom - rect.top) * viewport.width,
        ));
      }
      if (edges.isEmpty) continue;

      final edge = edges.reduce(
        (best, candidate) =>
            candidate.removedArea < best.removedArea ? candidate : best,
      );
      switch (edge.side) {
        case _EdgeSide.left:
          left = math.max(left, edge.position);
        case _EdgeSide.top:
          top = math.max(top, edge.position);
        case _EdgeSide.right:
          right = math.min(right, edge.position);
        case _EdgeSide.bottom:
          bottom = math.min(bottom, edge.position);
      }
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Offset? _rayIntersection(
    Offset origin,
    Offset vector,
    Rect bounds,
  ) {
    double? nearestScale;

    void consider(double scale, double x, double y) {
      if (scale <= 0 ||
          x < bounds.left ||
          x > bounds.right ||
          y < bounds.top ||
          y > bounds.bottom) {
        return;
      }
      if (nearestScale == null || scale < nearestScale!) {
        nearestScale = scale;
      }
    }

    if (vector.dx != 0) {
      var scale = (bounds.left - origin.dx) / vector.dx;
      consider(scale, bounds.left, origin.dy + vector.dy * scale);
      scale = (bounds.right - origin.dx) / vector.dx;
      consider(scale, bounds.right, origin.dy + vector.dy * scale);
    }
    if (vector.dy != 0) {
      var scale = (bounds.top - origin.dy) / vector.dy;
      consider(scale, origin.dx + vector.dx * scale, bounds.top);
      scale = (bounds.bottom - origin.dy) / vector.dy;
      consider(scale, origin.dx + vector.dx * scale, bounds.bottom);
    }
    return nearestScale == null ? null : origin + vector * nearestScale!;
  }
}

enum _EdgeSide { left, top, right, bottom }

final class _EdgeInset {
  final _EdgeSide side;
  final double position;
  final double removedArea;

  const _EdgeInset(this.side, this.position, this.removedArea);
}
