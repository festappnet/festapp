import 'dart:ui';

/// One screen-space magnet policy for moving and resizing every canvas object.
class TicketSnapResult {
  final Rect box;
  final double? x, y;
  const TicketSnapResult(this.box, this.x, this.y);
}

TicketSnapResult snapTicketBox(Rect box, Size area, Iterable<Rect> others,
    {required double zoom,
    double? gridStep,
    Offset? anchor,
    bool widthOnly = false,
    double minRatio = 0,
    double maxRatio = double.infinity}) {
  final xs = <double>[0, area.width / 2, area.width];
  final ys = <double>[0, area.height / 2, area.height];
  for (final other in others) {
    xs.addAll([other.left, other.center.dx, other.right]);
    ys.addAll([other.top, other.center.dy, other.bottom]);
  }
  final corner = anchor == null
      ? null
      : Offset(anchor.dx == box.left ? box.right : box.left,
          anchor.dy == box.top ? box.bottom : box.top);
  final ex =
      corner == null ? [box.left, box.center.dx, box.right] : [corner.dx];
  final ey =
      corner == null ? [box.top, box.center.dy, box.bottom] : [corner.dy];
  if (gridStep != null && gridStep > 0) {
    xs.addAll(ex.map((v) => (v / gridStep).round() * gridStep));
    ys.addAll(ey.map((v) => (v / gridStep).round() * gridStep));
  }
  (double, double?) nearest(List<double> edges, List<double> targets) {
    var distance = 5 / zoom;
    double correction = 0;
    double? guide;
    for (final edge in edges) {
      for (final target in targets) {
        final d = target - edge;
        if (d.abs() < distance) {
          distance = d.abs();
          correction = d;
          guide = target;
        }
      }
    }
    return (correction, guide);
  }

  final (dx, gx) = nearest(ex, xs);
  final (dy, gy) = nearest(ey, ys);
  if (anchor == null)
    return TicketSnapResult(box.shift(Offset(dx, dy)), gx, gy);
  if (widthOnly) {
    final ratio = (1 + dx / box.width);
    if (gx == null || ratio < minRatio || ratio > maxRatio)
      return TicketSnapResult(box, null, null);
    return TicketSnapResult(
        Rect.fromLTWH(box.left, box.top, box.width + dx, box.height), gx, null);
  }
  final rx = gx == null
      ? null
      : (corner!.dx + dx - anchor.dx) / (corner.dx - anchor.dx);
  final ry = gy == null
      ? null
      : (corner!.dy + dy - anchor.dy) / (corner.dy - anchor.dy);
  final useX = rx != null && rx >= minRatio && rx <= maxRatio;
  final useY = ry != null && ry >= minRatio && ry <= maxRatio;
  if (!useX && !useY) return TicketSnapResult(box, null, null);
  final horizontal = useX && (!useY || dx.abs() <= dy.abs());
  final ratio = horizontal ? rx : ry!;
  final next = Rect.fromPoints(anchor, anchor + (corner! - anchor) * ratio);
  // Show only lines the aspect-preserving resize actually reaches.
  final moved = anchor + (corner - anchor) * ratio;
  return TicketSnapResult(
      next,
      gx != null && (moved.dx - gx).abs() < .001 ? gx : null,
      gy != null && (moved.dy - gy).abs() < .001 ? gy : null);
}
