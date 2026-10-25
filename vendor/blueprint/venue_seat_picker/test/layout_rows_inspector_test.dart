import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';

void main() {
  testWidgets(
    'row and column controls retain curved seat identities and create atomic history',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final original = rowLayout(
        rows: 2,
        seatsPerRow: 4,
        arc: 3,
        spacing: 100,
        rowSpacing: 110,
        seating: const TableSeating(width: 77.5, height: 77.5),
        x: 300,
        y: 200,
      );
      final root = original.nodes.firstWhere((n) => n.parentId == null);
      final c = VenueLayoutController(original)..select({root.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Number of rows'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Seats per row'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Curvature'), findsOneWidget);
      final slider = tester.widget<Slider>(find.byType(Slider));
      slider.onChangeStart!(3);
      slider.onChanged!(6);
      slider.onChangeEnd!(6);
      await tester.pumpAndSettle();
      expect(rowLayoutParameters(c.document, root.id)['arc'], 6);
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.tap(find.byTooltip('Add row'));
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(12));
      expect(rowLayoutParameters(c.document, root.id)['arc'], 3);
      expect(
        c.document.nodes
            .where((n) => n.kind == 'seat')
            .every((n) => n.width == 77.5 && n.height == 77.5),
        isTrue,
      );
      for (final seat in original.nodes.where((n) => n.kind == 'seat')) {
        expect(c.document.nodes.any((n) => n.id == seat.id), true);
      }
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      final columnField = find.widgetWithText(TextField, 'Seats per row');
      await tester.enterText(columnField, '5');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(10));
      expect(rowLayoutParameters(c.document, root.id)['arc'], 3);
      expect(c.document.nodes.firstWhere((n) => n.id == root.id).x, root.x);
      expect(validateDocument(c.document), isEmpty);
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );

  testWidgets('row count cannot be fractional or remove the last row', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = rowLayout(rows: 1, seatsPerRow: 4, arc: 3, x: 300, y: 200);
    final c = VenueLayoutController(original)
      ..select({original.nodes.first.id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final remove = tester.widget<IconButton>(
      find.byWidgetPredicate(
        (w) => w is IconButton && w.tooltip == 'Remove row',
      ),
    );
    expect(remove.onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Number of rows'),
      '1.5',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, false);
  });
  testWidgets('rows split preserves seat IDs and geometry and supports undo', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = rowLayout(rows: 2, seatsPerRow: 3, arc: 4);
    final root = original.nodes.firstWhere(
      (n) => n.assembly?['kind'] == 'rows',
    );
    final c = VenueLayoutController(original)..select({root.id});
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final split = find.text('Split into seats');
    await tester.ensureVisible(split);
    await tester.tap(split);
    await tester.pumpAndSettle();
    expect(c.document.nodes.any((n) => n.id == root.id), false);
    expect(
      c.document.nodes.map((n) => n.id).toSet(),
      original.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
    );
    expect(c.document.attachments, isEmpty);
    expect(validateDocument(c.document), isEmpty);
    for (final seat in c.document.nodes) {
      expect(
        worldMatrix(c.document, seat),
        worldMatrix(
          original,
          original.nodes.firstWhere((n) => n.id == seat.id),
        ),
      );
    }
    c.undo();
    expect(c.document.toJson(), original.toJson());
  });

  test(
    'row labels span blocks and long rows, retaining explicit seat names on resize',
    () {
      final wide = rowLayout(rows: 2, seatsPerRow: 28);
      final names = wide.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.label)
          .toList();
      expect(names.take(2), ['1A', '1B']);
      expect(names[25], '1Z');
      expect(names[26], '1AA');
      expect(names[28], '2A');
      final old = rowLayout(rows: 2, seatsPerRow: 3, blocks: 2);
      final custom = old.nodes.firstWhere(
        (n) => n.properties['slot'] == '0:0:1',
      );
      final before = old.copyWith(
        nodes: old.nodes
            .map((n) => n.id == custom.id ? n.copyWith(label: 'VIP') : n)
            .toList(),
      );
      final root = before.nodes.firstWhere(
        (n) => n.assembly?['kind'] == 'rows',
      );
      final next = reconcileAssembly(
        before,
        root.id,
        rowLayout(rows: 2, seatsPerRow: 4, blocks: 2),
      );
      expect(next.nodes.firstWhere((n) => n.id == custom.id).label, 'VIP');
      expect(
        next.nodes.firstWhere((n) => n.properties['slot'] == '0:1:0').label,
        '1E',
      );
      expect(
        next.nodes.firstWhere((n) => n.properties['slot'] == '1:0:0').label,
        '2A',
      );
      expect(validateDocument(next), isEmpty);
    },
  );
}
