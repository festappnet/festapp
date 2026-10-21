import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'tall plan pans freely within half-visible bounds without recentering',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: VenueLayoutDocument.empty().copyWith(
                canvas: {
                  'x': 100.0,
                  'y': 200.0,
                  'width': 400.0,
                  'height': 1600.0,
                },
              ),
              compactZoomControls: true,
              pan: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final surface = find.byType(LayoutSceneSurface);
      LayoutScenePainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      void expectCentered() {
        final p = painter();
        final point = MatrixUtils.transformPoint(
          p.camera!.value,
          p.offset + const Offset(300, 1000) * p.scale,
        );
        expect(point.dx, closeTo(500, .001));
      }

      expectCentered();
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(150, 250),
          scrollDelta: Offset(0, -180),
        ),
      );
      await tester.pumpAndSettle();
      final beforePan = painter().camera!.value.clone();
      await tester.drag(surface, const Offset(-300, 80));
      await tester.pumpAndSettle();
      expect(
        painter().camera!.value.entry(0, 3),
        isNot(closeTo(beforePan.entry(0, 3), .001)),
      );
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          position: Offset(800, 450),
          scrollDelta: Offset(0, 1000),
        ),
      );
      await tester.pumpAndSettle();
      for (final movement in [
        const Offset(-5000, -5000),
        const Offset(10000, 10000),
      ]) {
        await tester.drag(surface, movement);
        await tester.pumpAndSettle();
        final p = painter();
        final start = MatrixUtils.transformPoint(
          p.camera!.value,
          p.offset + const Offset(100, 200) * p.scale,
        );
        final end = MatrixUtils.transformPoint(
          p.camera!.value,
          p.offset + const Offset(500, 1800) * p.scale,
        );
        final visibleWidth = math.min(1000, end.dx) - math.max(0, start.dx);
        final visibleHeight = math.min(600, end.dy) - math.max(0, start.dy);
        expect(
          visibleWidth,
          greaterThanOrEqualTo(math.min((end.dx - start.dx) / 2, 500) - .01),
        );
        expect(
          visibleHeight,
          greaterThanOrEqualTo(math.min((end.dy - start.dy) / 2, 300) - .01),
        );
      }
    },
  );

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
