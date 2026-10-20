import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<void> open(WidgetTester tester, VenueLayoutController c) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
        ),
      );

  test('text style never changes the physical table resize constraint', () {
    final source = tableLayout(shape: 'rect', count: 0, width: 180, height: 80);
    final table = source.nodes.single;
    final c = VenueLayoutController(source);
    addTearDown(c.dispose);
    final before = c.constrainTableDimensions(table, 60, 40);
    final styled = table.copyWith(
      label: 'A very long label',
      style: {
        'label': {'size': 200, 'weight': 700},
      },
    );
    c.updateNode(styled);
    final after = c.constrainTableDimensions(c.document.nodes.single, 60, 40);
    expect(after.width, before.width);
    expect(after.height, before.height);
    c.resizeObject(table.id, 60, 40);
    expect(c.error, isNull);
    expect(c.document.nodes.single.width, 60);
    expect(c.document.nodes.single.height, 40);
    c.undo();
    expect(c.document.nodes.single.toJson(), styled.toJson());
  });
  testWidgets('resizing a wrapped table preserves chair size and one undo', (
    tester,
  ) async {
    final tableDoc = tableLayout(shape: 'roundedRect', count: 6);
    final table = tableDoc.nodes.firstWhere((n) => n.kind == 'table');
    final wrapper = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      width: 1,
      height: 1,
    );
    final original = tableDoc.copyWith(
      nodes: [
        wrapper,
        for (final node in tableDoc.nodes)
          if (node.id == table.id)
            node.copyWith(parentId: wrapper.id)
          else
            node,
      ],
    );
    final c = VenueLayoutController(original)..select({wrapper.id});
    await open(tester, c);
    final bounds = selectionBounds(original, {wrapper.id});
    final corner = Offset(
      bounds['x']! + bounds['width']!,
      bounds['y']! + bounds['height']!,
    );
    var updates = 0;
    c.addListener(() => updates++);
    surface(tester).onHandleStart!('Resize se', corner);
    for (var i = 1; i <= 100; i++) {
      surface(tester).onDragUpdate!(
        corner + Offset(i.toDouble(), i.toDouble()),
      );
    }
    expect(updates, lessThanOrEqualTo(1));
    surface(tester).onDragEnd!();
    final enlarged = c.document.nodes.firstWhere((n) => n.id == table.id);
    expect(enlarged.width, greaterThan(table.width));
    for (final seat in tableDoc.nodes.where((n) => n.kind == 'seat')) {
      final after = c.document.nodes.firstWhere((n) => n.id == seat.id);
      expect(after.width, seat.width);
      expect(after.height, seat.height);
    }
    await tester.pump();
    c.undo();
    expect(c.document, same(original));
    expect(c.canUndo, isFalse);
  });

  testWidgets(
    'free imported chairs reject a resize that would overwrite their placement',
    (tester) async {
      final tableDoc = tableLayout(shape: 'roundedRect', count: 6);
      final table = tableDoc.nodes.firstWhere((n) => n.kind == 'table');
      final wrapper = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        width: 1,
        height: 1,
      );
      final original = tableDoc.copyWith(
        nodes: [
          wrapper,
          for (final node in tableDoc.nodes)
            if (node.id == table.id)
              node.copyWith(parentId: wrapper.id)
            else
              node,
        ],
        attachments: [
          for (final a in tableDoc.attachments)
            {
              ...a,
              'placement': {'mode': 'free'},
            },
        ],
      );
      final c = VenueLayoutController(original)..select({wrapper.id});
      await open(tester, c);
      final bounds = selectionBounds(original, {wrapper.id});
      final corner = Offset(
        bounds['x']! + bounds['width']!,
        bounds['y']! + bounds['height']!,
      );
      surface(tester).onHandleStart!('Resize se', corner);
      surface(tester).onDragUpdate!(corner + const Offset(300, 300));
      surface(tester).onDragEnd!();
      expect(c.error, contains('Fixed chairs'));
      expect(c.document, same(original));
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'circle resizing stays circular with Shift and restores removed seats on undo',
    (tester) async {
      final original = tableLayout(
        shape: 'ellipse',
        width: 160,
        height: 160,
        count: 8,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(original)..select({table.id});
      await open(tester, c);
      final corner = Offset(table.x + 80, table.y + 80);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner - const Offset(60, 20));
      await tester.pump();
      final resized = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(resized.width, 100);
      expect(resized.height, 100);
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(6));
      await tester.pump();
      expect(
        find.text('Seats removed: 2. Undo restores them.'),
        findsOneWidget,
      );
      surface(tester).onDragEnd!();
      c.undo();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner + const Offset(40, 10));
      surface(tester).onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final ellipse = c.document.nodes.firstWhere((n) => n.id == table.id);
      expect(ellipse.width, 200);
      expect(ellipse.height, ellipse.width);
      expect(ellipse.surface!['type'], 'circle');
    },
  );

  testWidgets(
    'protected shrink displays clear notice and rolls back without history',
    (tester) async {
      final original = tableLayout(
        shape: 'round',
        width: 160,
        height: 160,
        count: 8,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final protected = original.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final c = VenueLayoutController(
        original,
        protectedSeatIds: () => protected,
      )..select({table.id});
      await open(tester, c);
      final corner = Offset(table.x + 80, table.y + 80);
      surface(tester).onHandleStart!('Resize', corner);
      surface(tester).onDragUpdate!(corner - const Offset(60, 20));
      await tester.pump();
      expect(
        find.text('Reserved or blocked seats prevent shrinking this table.'),
        findsOneWidget,
      );
      expect(c.document.toJson(), original.toJson());
      surface(tester).onDragEnd!();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      expect(
        c.error,
        'Reserved or blocked seats prevent shrinking this table.',
      );
    },
  );

  test('live host protection applies to history and generic removal', () {
    final original = tableLayout(
      shape: 'round',
      width: 160,
      height: 160,
      count: 8,
    );
    final protected = <String>{};
    final c = VenueLayoutController(
      original,
      protectedSeatIds: () => protected,
    );
    addTearDown(c.dispose);
    final extra = LayoutNode(id: newLayoutId(), kind: 'seat', x: 800, y: 600);
    expect(c.apply(original.copyWith(nodes: [...original.nodes, extra])), true);
    protected.add(extra.id);
    c.undo();
    expect(c.document.nodes.any((n) => n.id == extra.id), true);
    expect(c.canUndo, true);
    expect(c.apply(original), false);
    protected.clear();
    c.undo();
    expect(c.document.toJson(), original.toJson());
  });
}
