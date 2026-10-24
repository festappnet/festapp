import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets('touch pans from blank viewport outside the transformed grid', (
    tester,
  ) async {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 2, columns: 20, seats: const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: VenueSeatViewer(controller: controller),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.transformationController.value = Matrix4.diagonal3Values(
      2,
      2,
      1,
    );
    await tester.pump();
    final rect = tester.getRect(find.byType(InteractiveViewer));
    final start = rect.topLeft + const Offset(200, 20);
    final scene = controller.transformationController.toScene(
      start - rect.topLeft,
    );
    expect(scene.dy, lessThan(0), reason: 'Start lies above the rendered grid');
    final before = controller.transformationController.value.getTranslation().x;
    await tester.dragFrom(start, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(
      controller.transformationController.value.getTranslation().x,
      lessThan(before - 40),
    );
  });

  testWidgets(
    'grid tap slop is radial and semantic activation uses one handler',
    (tester) async {
      final controller =
          VenueSeatController<VenueSeat, Object>(
            adapter: venueSeatAdapter,
          )..loadPlan(
            rows: 3,
            columns: 5,
            seats: const [VenueSeat(id: 'seat', position: SeatPosition(1, 2))],
          );
      addTearDown(controller.dispose);
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 400,
              height: 300,
              child: VenueSeatViewer(
                controller: controller,
                onSeatPressed: (_) => calls++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewport = tester.getTopLeft(find.byType(InteractiveViewer));
      Offset screen(Offset world) =>
          viewport +
          MatrixUtils.transformPoint(
            controller.transformationController.value,
            world,
          );
      for (final zoom in [.5, 1.0, 2.0]) {
        controller.transformationController.value = Matrix4.diagonal3Values(
          zoom,
          zoom,
          1,
        );
        await tester.pump();
        await tester.tapAt(screen(Offset(120 + 7 / zoom, 60)));
        await tester.pumpAndSettle();
        final before = calls;
        expect(before, greaterThan(0));
        await tester.tapAt(screen(Offset(120 + 9 / zoom, 60)));
        await tester.pumpAndSettle();
        expect(calls, before);
        await tester.tapAt(screen(Offset(120 + 6 / zoom, 80 + 6 / zoom)));
        await tester.pumpAndSettle();
        expect(calls, before, reason: 'Diagonal distance exceeds 8 logical px');
      }
      final semantics = tester.ensureSemantics();
      final target = find.byWidgetPredicate(
        (w) => w is Semantics && w.properties.onTap != null,
      );
      final before = calls;
      tester
          .renderObject(target)
          .owner!
          .semanticsOwner!
          .performAction(tester.getSemantics(target).id, SemanticsAction.tap);
      expect(calls, before + 1);
      semantics.dispose();
      final start = screen(const Offset(100, 60));
      final finger = await tester.startGesture(start);
      await finger.cancel();
      await tester.pumpAndSettle();
      expect(calls, before + 1);
      await tester.dragFrom(start, const Offset(-60, 0));
      await tester.pumpAndSettle();
      expect(calls, before + 1);
    },
  );

  testWidgets('coordinate tap preserves tap tooltip without selecting', (
    tester,
  ) async {
    final controller =
        VenueSeatController<VenueSeat, Object>(adapter: venueSeatAdapter)
          ..loadPlan(
            rows: 1,
            columns: 1,
            seats: const [
              VenueSeat(
                id: 'A',
                position: SeatPosition(0, 0),
                label: 'Seat details',
              ),
            ],
          );
    addTearDown(controller.dispose);
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 400,
            height: 300,
            child: VenueSeatViewer(
              controller: controller,
              onSeatPressed: (_) => calls++,
              shouldShowTooltipOnTap: (_) => true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final at = tester.getCenter(find.byType(VenueSeatMarker));
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.text('Seat details'), findsOneWidget);
    expect(controller.slots.single.isTooltipHighlighted, true);
    expect(calls, 0);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(find.text('Seat details'), findsNothing);
    expect(controller.slots.single.isTooltipHighlighted, false);
    expect(calls, 0);
  });

  for (final kind in ['viewer', 'picker', 'editor']) {
    testWidgets('zoomed $kind cannot be dragged outside the viewport', (
      tester,
    ) async {
      final controller = VenueSeatController<VenueSeat, Object>(
        adapter: venueSeatAdapter,
      )..loadPlan(rows: 20, columns: 20, seats: const []);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: Center(
              child: SizedBox(
                width: 400,
                height: 300,
                child: switch (kind) {
                  'editor' => VenueSeatEditor(
                    controller: controller,
                    editing: SeatEditingDelegate<VenueSeat>(
                      create: (position, status) => VenueSeat(
                        id: position,
                        position: position,
                        status: status,
                      ),
                      withStatus: (seat, status) =>
                          seat.copyWith(status: status),
                    ),
                  ),
                  'picker' => VenueSeatPicker(controller: controller),
                  _ => VenueSeatViewer(
                    controller: controller,
                    editorMode: true,
                  ),
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      controller.transformationController.value = Matrix4.diagonal3Values(
        2,
        2,
        1,
      );
      final viewer = find.byType(InteractiveViewer);
      for (final direction in [
        const Offset(1000, 1000),
        const Offset(-5000, -5000),
      ]) {
        await tester.drag(viewer, direction);
        await tester.pumpAndSettle();
        final matrix = controller.transformationController.value;
        final position = matrix.getTranslation();
        final scale = matrix.getMaxScaleOnAxis();
        expect(position.x, lessThanOrEqualTo(24));
        expect(position.y, lessThanOrEqualTo(24));
        expect(
          position.x + controller.columns * controller.seatSize * scale,
          greaterThanOrEqualTo(400 - 24),
        );
        expect(
          position.y + controller.rows * controller.seatSize * scale,
          greaterThanOrEqualTo(tester.getSize(viewer).height - 24),
        );
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('tall editor plan is physically centered in loose column space', (
    tester,
  ) async {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 72, columns: 40, seats: const []);
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 550,
            child: Column(
              children: [
                const SizedBox(height: 50, width: 700),
                Flexible(
                  child: VenueSeatViewer(
                    controller: controller,
                    editorMode: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final scene = tester.renderObject<RenderBox>(
      find
          .descendant(
            of: find.byType(InteractiveViewer),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    final center = scene.localToGlobal(scene.size.center(Offset.zero));
    expect(
      center.dx,
      closeTo(350, 0.1),
      reason:
          'viewer=${tester.getRect(find.byType(InteractiveViewer))}, scene=${scene.size}, matrix=${controller.transformationController.value}',
    );
    expect(center.dy, closeTo(300, 0.1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('small plans stay centered after zoom and viewport resize', (
    tester,
  ) async {
    final controller = VenueSeatController<VenueSeat, Object>(
      adapter: venueSeatAdapter,
    )..loadPlan(rows: 1, columns: 1, seats: const []);
    final size = ValueNotifier(const Size(400, 300));
    addTearDown(controller.dispose);
    addTearDown(size.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: Center(
            child: ValueListenableBuilder<Size>(
              valueListenable: size,
              builder: (context, viewport, _) => SizedBox(
                width: viewport.width,
                height: viewport.height,
                child: VenueSeatViewer(
                  controller: controller,
                  editorMode: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    controller.transformationController.value = Matrix4.diagonal3Values(2, 2, 1)
      ..setTranslationRaw(-1000, 1000, 0);
    await tester.drag(
      find.byType(InteractiveViewer),
      const Offset(1000, -1000),
    );
    await tester.pumpAndSettle();
    void expectCentered() {
      final matrix = controller.transformationController.value;
      final content = controller.seatSize * matrix.getMaxScaleOnAxis();
      final position = matrix.getTranslation();
      expect(position.x, closeTo((size.value.width - content) / 2, 0.001));
      expect(position.y, closeTo((size.value.height - content) / 2, 0.001));
    }

    expectCentered();
    size.value = const Size(250, 200);
    await tester.pumpAndSettle();
    expectCentered();
    controller.fitToViewport();
    await tester.pumpAndSettle();
    expectCentered();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
