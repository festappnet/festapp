import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

Future<void> mountInspector(
  WidgetTester tester,
  VenueLayoutController c,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 340,
          height: 500,
          child: ListenableBuilder(
            listenable: c,
            builder: (_, _) => LayoutInspector(
              controller: c,
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

void main() {
  testWidgets(
    'scroll over a focused number never changes the plan or undo history',
    (tester) async {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'Table A',
        x: 300,
        y: 300,
        width: 180,
        height: 100,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table]),
      );
      addTearDown(c.dispose);
      c.select({table.id});
      await mountInspector(tester, c);
      final field = find.widgetWithText(TextField, 'Font size');
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      final before = c.document;
      var notifications = 0;
      c.addListener(() => notifications++);
      final scroll = tester
          .state<ScrollableState>(
            find
                .descendant(
                  of: find.byKey(
                    ValueKey('inspector-context-false:${table.id}'),
                  ),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      final beforeOffset = scroll.pixels;
      final position = tester.getCenter(field);
      for (var i = 0; i < 12; i++) {
        await tester.sendEventToBinding(
          PointerScrollEvent(
            position: position,
            scrollDelta: const Offset(0, 20),
          ),
        );
        await tester.pump();
      }
      expect(scroll.pixels, greaterThan(beforeOffset));
      expect(c.document, same(before));
      expect(c.canUndo, isFalse);
      expect(notifications, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final kind in ['table', 'shape', 'text', 'capacityArea']) {
    testWidgets(
      '$kind exposes working font size and bold without geometry changes',
      (tester) async {
        final node = LayoutNode(
          id: newLayoutId(),
          kind: kind,
          surface: kind == 'table' ? const {'type': 'rect'} : null,
          label: 'Label',
          x: 300,
          y: 300,
          width: 180,
          height: 100,
          properties: kind == 'text' ? {'text': 'Label'} : {},
        );
        final child = LayoutNode(
          id: newLayoutId(),
          kind: 'table',
          parentId: node.id,
          label: 'Label',
          width: 180,
          height: 100,
          surface: const {'type': 'rect'},
        );
        final target = kind == 'group' ? child : node;
        final doc = VenueLayoutDocument.empty().copyWith(
          nodes: [node, if (kind == 'group') child],
        );
        final c = VenueLayoutController(
          doc,
          resources: (await tester.runAsync(loadLayoutFixtureResources))!,
        );
        addTearDown(c.dispose);
        c.select({node.id});
        await mountInspector(tester, c);
        final size = find.widgetWithText(TextField, 'Font size');
        await tester.ensureVisible(size);
        await tester.enterText(size, '32');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        final bold = find.byTooltip('Bold');
        await tester.ensureVisible(bold);
        await tester.tap(bold);
        await tester.pumpAndSettle();
        final updated = c.document.nodes.firstWhere((n) => n.id == target.id);
        expect(updated.style['label']['size'], 32);
        expect(updated.style['label']['weight'], 700);
        expect(
          [updated.x, updated.y, updated.width, updated.height, updated.label],
          [target.x, target.y, target.width, target.height, target.label],
        );
        final italic = find.byTooltip('Italic');
        await tester.tap(italic);
        await tester.pumpAndSettle();
        expect(
          c.document.nodes
              .firstWhere((n) => n.id == target.id)
              .style['label']['italic'],
          isTrue,
        );
        await tester.tap(bold);
        await tester.pumpAndSettle();
        final combination = c.document.nodes
            .firstWhere((n) => n.id == target.id)
            .style['label'];
        expect(combination['weight'], 400);
        expect(combination['italic'], isTrue);
        c.undo();
        c.undo();
        c.undo();
        c.undo();
        expect(c.document.toJson(), doc.toJson());
        expect(tester.takeException(), isNull);
      },
    );
  }
}
