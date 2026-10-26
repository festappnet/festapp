import 'package:material_ui/material_ui.dart';

/// Flat, renderer-neutral current-location mark. It deliberately echoes a map
/// pin without sharing the narrower silhouette used by place markers.
class MapCurrentLocationDrop extends StatelessWidget {
  final double size;
  final Color color;

  const MapCurrentLocationDrop({
    required this.size,
    required this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size.square(size),
        painter: _MapCurrentLocationDropPainter(color),
      );
}

class _MapCurrentLocationDropPainter extends CustomPainter {
  static const _liveDotOuterRadiusFactor = 0.21;
  static const _liveDotInnerRadiusFactor = 0.105;

  final Color color;

  const _MapCurrentLocationDropPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final drop = Path()
      ..moveTo(w * 0.5, h)
      ..cubicTo(w * 0.45, h * 0.88, w * 0.1, h * 0.64, w * 0.1, h * 0.4)
      ..cubicTo(w * 0.1, h * 0.17, w * 0.28, 0, w * 0.5, 0)
      ..cubicTo(w * 0.72, 0, w * 0.9, h * 0.17, w * 0.9, h * 0.4)
      ..cubicTo(w * 0.9, h * 0.64, w * 0.55, h * 0.88, w * 0.5, h)
      ..close();

    canvas.drawPath(drop, Paint()..color = color);

    final dotCenter = Offset(w * 0.5, h * 0.38);
    canvas
      ..drawCircle(
        dotCenter,
        w * _liveDotOuterRadiusFactor,
        Paint()..color = Colors.white,
      )
      ..drawCircle(
        dotCenter,
        w * _liveDotInnerRadiusFactor,
        Paint()..color = color,
      );
  }

  @override
  bool shouldRepaint(_MapCurrentLocationDropPainter oldDelegate) =>
      color != oldDelegate.color;
}
