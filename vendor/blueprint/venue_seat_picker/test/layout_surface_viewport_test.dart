import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets('changing mode viewport preserves zoom and world center', (
    tester,
  ) async {
    final viewport = ValueNotifier(const Size(400, 300));
    addTearDown(viewport.dispose);
    final document = VenueLayoutDocument.empty();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: ValueListenableBuilder<Size>(
              valueListenable: viewport,
              builder: (_, size, _) => SizedBox(
                width: size.width,
                height: size.height,
                child: LayoutSceneSurface(document: document, pan: true),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final surface = find.byType(LayoutSceneSurface);
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(surface),
        scrollDelta: const Offset(0, -200),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(surface, const Offset(30, 20));
    await tester.pumpAndSettle();
    LayoutScenePainter painter() =>
        tester
                .widget<CustomPaint>(
                  find.descendant(
                    of: surface,
                    matching: find.byWidgetPredicate(
                      (w) =>
                          w is CustomPaint && w.painter is LayoutScenePainter,
                    ),
                  ),
                )
                .painter!
            as LayoutScenePainter;
    Offset worldCenter(LayoutScenePainter p) =>
        (p.camera!.toScene(viewport.value.center(Offset.zero)) - p.offset) /
        p.scale;
    double zoom(LayoutScenePainter p) {
      final m = p.camera!.value;
      return p.scale *
          math.sqrt(
            m.entry(0, 0) * m.entry(0, 0) + m.entry(1, 0) * m.entry(1, 0),
          );
    }

    final before = painter(),
        center = worldCenter(before),
        beforeZoom = zoom(before);
    viewport.value = const Size(500, 300);
    await tester.pumpAndSettle();
    final after = painter();
    expect(
      (worldCenter(after) - center).distance,
      lessThan(.01),
      reason: 'Opening/closing the object palette must retain the viewed area',
    );
    expect(zoom(after), closeTo(beforeZoom, .0001));
    expect(tester.takeException(), isNull);
  });
}
