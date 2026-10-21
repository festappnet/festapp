import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Find the public editor's rendered gesture surface without private imports.
/// Camera assertions inspect its CustomPaint output; SDK painter fields remain
/// a test coupling, localized here rather than widening the vendor API.
Finder layoutCanvas() =>
    find.byKey(const ValueKey('layout-map-gesture-surface'));

dynamic layoutPainter(WidgetTester tester) => tester
    .widgetList<CustomPaint>(
        find.descendant(of: layoutCanvas(), matching: find.byType(CustomPaint)))
    .map((widget) => widget.painter)
    .where((painter) => painter != null)
    .single;

Offset layoutPoint(WidgetTester tester, Offset scenePoint) {
  final painter = layoutPainter(tester);
  final canvas = painter.scene['canvas'] as Map;
  final origin = Offset((canvas['x'] as num? ?? 0).toDouble(),
      (canvas['y'] as num? ?? 0).toDouble());
  return tester.getTopLeft(layoutCanvas()) +
      MatrixUtils.transformPoint(
          painter.camera.value,
          (scenePoint - origin) * (painter.scale as double) +
              (painter.offset as Offset));
}

Future<void> doubleTapLayout(WidgetTester tester, Offset scenePoint) async {
  final point = layoutPoint(tester, scenePoint);
  await tester.tapAt(point);
  await tester.pump(const Duration(milliseconds: 60));
  await tester.tapAt(point);
}
