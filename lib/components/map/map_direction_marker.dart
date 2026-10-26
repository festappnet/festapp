import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

class MapDirectionMarker extends StatelessWidget {
  static const halfApexAngleDegrees = 25.0;

  final Color color;
  final double bodyPixels;

  const MapDirectionMarker({
    required this.color,
    required this.bodyPixels,
    super.key,
  });

  static Size sizeFor(double bodyPixels) => Size(
        bodyPixels * 2 * math.tan(halfApexAngleDegrees * math.pi / 180),
        bodyPixels,
      );

  @override
  Widget build(BuildContext context) {
    final size = sizeFor(bodyPixels);
    return CustomPaint(
      size: size,
      painter: _DirectionTrianglePainter(color),
    );
  }
}

class _DirectionTrianglePainter extends CustomPainter {
  final Color color;

  const _DirectionTrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..moveTo(size.width / 2, 0)
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close(),
      Paint()
        ..color = color
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(_DirectionTrianglePainter oldDelegate) =>
      oldDelegate.color != color;
}
