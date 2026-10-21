import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

class _CountingPainter extends LayoutScenePainter {
  _CountingPainter({
    required super.scene,
    required super.camera,
    required this.onPaint,
  }) : super(
         resources: const {},
         selected: const {},
         scale: 1,
         offset: Offset.zero,
         canvasColor: Colors.white,
         selectionColor: Colors.blue,
       );
  final VoidCallback onPaint;
  @override
  void paint(Canvas canvas, Size size) {
    onPaint();
    super.paint(canvas, size);
  }
}

void main() {
  testWidgets(
    'unchanged canvas avoids repaint while camera and real edits remain live',
    (tester) async {
      final node = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
      final document = VenueLayoutDocument.empty().copyWith(nodes: [node]);
      final scene = compileScene(document);
      final revision = ValueNotifier(0);
      final camera = TransformationController();
      addTearDown(revision.dispose);
      addTearDown(camera.dispose);
      var paints = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<int>(
              valueListenable: revision,
              builder: (_, value, _) => CustomPaint(
                size: const Size(400, 400),
                painter: _CountingPainter(
                  scene: value < 2
                      ? scene
                      : compileScene(
                          document.copyWith(nodes: [node.copyWith(x: 140)]),
                        ),
                  camera: camera,
                  onPaint: () => paints++,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final initial = paints;
      expect(initial, greaterThan(0));
      revision.value = 1;
      await tester.pump();
      expect(
        paints,
        initial,
        reason: 'Hover/tooltips must not redraw an unchanged map',
      );
      revision.value = 2;
      await tester.pump();
      expect(paints, greaterThan(initial));
      final beforeCamera = paints;
      camera.value = Matrix4.translationValues(10, 0, 0);
      await tester.pump();
      expect(
        paints,
        greaterThan(beforeCamera),
        reason: 'Camera repaint listener remains active',
      );
    },
  );
  testWidgets('equal presentation updates do not animate an unchanged scene', (
    tester,
  ) async {
    final node = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100);
    final document = VenueLayoutDocument.empty().copyWith(nodes: [node]);
    final revision = ValueNotifier(0);
    addTearDown(revision.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (_, value, _) => LayoutSceneSurface(
              document: document,
              selected: const {},
              presentation: {
                node.id: {'fill': value < 2 ? '#267329FF' : '#FF0000FF'},
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.binding.transientCallbackCount, 0);
    revision.value = 1;
    await tester.pump();
    expect(
      tester.binding.transientCallbackCount,
      0,
      reason:
          'A new map with unchanged seat states must not schedule reflow frames',
    );
    revision.value = 2;
    await tester.pump();
    expect(
      tester.binding.transientCallbackCount,
      greaterThan(0),
      reason: 'An actual state change retains the transition',
    );
    await tester.pumpAndSettle();
  });
}
