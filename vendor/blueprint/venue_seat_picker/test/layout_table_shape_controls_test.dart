import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    VenueLayoutController controller,
  ) async {
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            child: ListenableBuilder(
              listenable: controller,
              builder: (_, _) => LayoutInspector(
                controller: controller,
                cornerPivot: false,
                onPivotChanged: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, String label) async {
    final control = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(control);
    await tester.tap(control);
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'manual chair can return to automatic layout with identity and undo intact',
    (tester) async {
      final original = tableLayout(shape: 'rect');
      final seat = original.nodes.firstWhere((n) => n.kind == 'seat');
      final c = VenueLayoutController(original)..select({seat.id});
      c.updateNode(seat.copyWith(x: seat.x - 250, y: seat.y - 180));
      final manual = c.document;
      expect(seatAttachment(manual, seat.id)?['placement']['mode'], 'free');
      await open(tester, c);
      final action = find.byKey(const ValueKey('restore-automatic-chair'));
      await tester.ensureVisible(action);
      await tester.tap(action);
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      expect(
        seatAttachment(c.document, seat.id)?['placement']['mode'],
        'automatic',
      );
      expect(
        c.document.nodes.map((n) => n.id).toSet(),
        original.nodes.map((n) => n.id).toSet(),
      );
      expect(
        find.byKey(const ValueKey('restore-automatic-chair')),
        findsNothing,
      );
      c.undo();
      expect(c.document.toJson(), manual.toJson());
    },
  );

  testWidgets(
    'seat stepper disables addition at table capacity and re-enables after removal',
    (tester) async {
      final base = tableLayout(shape: 'round', width: 180, count: 0);
      final table = base.nodes.firstWhere((node) => node.kind == 'table');
      final capacity = tableCapacity(table);
      final full = reflowTable(base, table.id, capacity);
      final c = VenueLayoutController(full)..select({table.id});
      await open(tester, c);
      IconButton add() => tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add_circle_outline),
      );
      expect(add().onPressed, isNull);
      await tester.tap(find.byTooltip('Remove one seat'));
      await tester.pumpAndSettle();
      expect(add().onPressed, isNotNull);
      await tester.tap(find.byTooltip('Add one seat'));
      await tester.pumpAndSettle();
      expect(add().onPressed, isNull);
      expect(c.error, isNull);
      expect(
        c.document.nodes.where((node) => node.kind == 'seat').length,
        capacity,
      );
    },
  );

  testWidgets(
    'tables and bars can be painted and drawn shapes convert to bars',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final polygon = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        width: 200,
        height: 200,
        properties: {
          'shape': 'polygon',
          'points': [
            [-100, -100],
            [100, -100],
            [100, 100],
            [-100, 100],
          ],
        },
      );
      final c = VenueLayoutController(VenueLayoutDocument(nodes: [polygon]))
        ..select({polygon.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paint table'), findsOneWidget);
      expect(find.text('Paint bar'), findsOneWidget);
      expect(find.text('Use as table'), findsNothing);
      expect(find.text('Use as bar'), findsNothing);
      expect(find.text('Table'), findsWidgets);
      expect(find.text('Round table'), findsWidgets);
      expect(c.dirty, isFalse);
    },
  );

  testWidgets(
    'table shapes switch both ways without changing seat identities',
    (tester) async {
      final original = tableLayout(
        shape: 'round',
        width: 200,
        height: 200,
        count: 4,
      );
      final table = original.nodes.firstWhere((node) => node.kind == 'table');
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({table.id});
      await open(tester, controller);
      expect(find.text('Preview count'), findsNothing);
      expect(find.text('Rotate around corner'), findsNothing);
      expect(find.text('Physical obstacle'), findsNothing);
      expect(find.text('Blocks seat placement'), findsNothing);
      expect(find.byTooltip('Add one seat'), findsOneWidget);
      expect(find.byTooltip('Remove one seat'), findsOneWidget);
      for (final entry in {
        'Rectangle': 'rect',
        'Custom outline': 'grid',
        'Round': 'circle',
      }.entries) {
        await choose(tester, entry.key);
        expect(
          controller.document.nodes
              .firstWhere((node) => node.id == table.id)
              .surface?['type'],
          entry.value,
        );
        if (entry.value == 'grid') {
          final points = localHull(
            controller.document.nodes.firstWhere((node) => node.id == table.id),
          );
          expect(points.length, 6);
          for (var i = 0; i < points.length; i++) {
            final a = points[i], b = points[(i + 1) % points.length];
            expect(a[0] == b[0] || a[1] == b[1], isTrue);
          }
        }
        expect(
          controller.document.nodes
              .where((node) => node.kind == 'seat')
              .map((node) => node.id)
              .toSet(),
          seatIds,
        );
        expect(
          controller.document.attachments
              .map((attachment) => attachment['seatId'])
              .toSet(),
          seatIds,
        );
        expect(
          controller.document.nodes
              .where((node) => seatIds.contains(node.id))
              .every((node) => node.parentId == table.id),
          isTrue,
        );
      }
      controller.undo();
      controller.undo();
      controller.undo();
      expect(controller.document, same(original));
    },
  );

  testWidgets(
    'imported table outlines remain intact until a basic shape is chosen',
    (tester) async {
      final base = tableLayout(
        shape: 'roundedRect',
        width: 200,
        height: 200,
        count: 4,
      );
      final table = base.nodes.firstWhere((node) => node.kind == 'table');
      final original = setTableSurfaceKind(base, table.id, 'grid');
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({table.id});
      await open(tester, controller);
      final control = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>).first,
      );
      expect(control.initialValue, 'polygon');
      expect(find.text('Custom outline'), findsOneWidget);
      expect(controller.document, same(original));
      expect(controller.canUndo, isFalse);
      await choose(tester, 'Round');
      expect(
        controller.document.nodes
            .firstWhere((node) => node.id == table.id)
            .surface?['type'],
        'circle',
      );
      expect(
        controller.document.nodes
            .where((node) => node.kind == 'seat')
            .map((node) => node.id)
            .toSet(),
        seatIds,
      );
      controller.undo();
      expect(controller.document, same(original));
    },
  );

  for (final bar in [false, true]) {
    testWidgets(
      '${bar ? 'bar' : 'table'} custom conversion and numeric resize use fixed modules',
      (tester) async {
        final table = LayoutNode(
          id: newLayoutId(),
          kind: 'table',
          label: 'Surface',
          x: 500,
          y: 400,
          width: 190,
          height: 110,
          properties: {
            if (bar) 'furniture': 'bar',
            if (bar) 'guestSide': 'bottom',
          },
          surface: const {'type': 'rect'},
        );
        final original = VenueLayoutDocument.empty().copyWith(nodes: [table]);
        final controller = VenueLayoutController(original)..select({table.id});
        await open(tester, controller);
        await choose(tester, 'Custom outline');
        final converted = controller.document.nodes.single;
        final step = bar ? barSurfaceModuleSize : tableSurfaceModuleSize;
        void expectGrid(LayoutNode surface) {
          expect(surface.width % step, closeTo(0, 1e-8));
          expect(surface.height % step, closeTo(0, 1e-8));
          final points = localHull(surface);
          for (final point in points) {
            expect((point[0] + surface.width / 2) % step, closeTo(0, 1e-8));
            expect((point[1] + surface.height / 2) % step, closeTo(0, 1e-8));
          }
        }

        expect(converted.surface?['type'], 'grid');
        expect(localHull(converted).length, 6);
        expectGrid(converted);
        final expected = resizeGridTableSurface(
          controller.document,
          table.id,
          converted.width + step * 1.3,
          converted.height,
        );
        await tester.pumpAndSettle();
        final geometry = find.text('Position and size');
        await tester.ensureVisible(geometry);
        await tester.tap(geometry);
        await tester.pumpAndSettle();
        final width = find.widgetWithText(TextField, 'Width');
        await tester.ensureVisible(width);
        await tester.enterText(width, '${converted.width + step * 1.3}');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(
          controller.document.nodes.single.toJson(),
          expected.nodes.single.toJson(),
        );
        expectGrid(controller.document.nodes.single);
        controller.undo();
        controller.undo();
        expect(controller.document, same(original));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'a smaller-capacity shape cannot silently remove protected seats',
    (tester) async {
      final template = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        width: 256,
        height: 256,

        surface: const {'type': 'rect'},
      );
      final count = tableCapacity(template);
      expect(
        tableCapacity(template.copyWith(surface: const {'type': 'circle'})),
        lessThan(count),
      );
      final original = tableLayout(
        shape: 'roundedRect',
        width: 256,
        height: 256,
        count: count,
        id: template.id,
      );
      final seatIds = original.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      final controller = VenueLayoutController(
        original,
        protectedSeatIds: () => seatIds,
      )..select({template.id});
      await open(tester, controller);
      await choose(tester, 'Round');
      expect(controller.document, same(original));
      expect(controller.canUndo, isFalse);
      expect(
        find.byKey(const ValueKey('layout-inspector-error')),
        findsOneWidget,
      );
    },
  );
}
