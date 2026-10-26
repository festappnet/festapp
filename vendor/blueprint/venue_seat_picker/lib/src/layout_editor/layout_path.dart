import 'dart:ui';

/// Shared canonical path decoding for painting and placement geometry.
Path layoutPath(List commands) {
  final p = Path();
  for (final raw in commands) {
    final c = raw as List;
    double v(int i) => (c[i] as num).toDouble();
    switch (c.first) {
      case 'M':
        p.moveTo(v(1), v(2));
      case 'L':
        p.lineTo(v(1), v(2));
      case 'Q':
        p.quadraticBezierTo(v(1), v(2), v(3), v(4));
      case 'C':
        p.cubicTo(v(1), v(2), v(3), v(4), v(5), v(6));
      case 'Z':
        p.close();
    }
  }
  return p;
}
