import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'transport uses count controls and rotation above its actual footprint',
    (tester) async {
      final doc = busLayout(decks: 2);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LayoutSceneSurface(
              document: doc,
              selected: {doc.nodes.first.id},
              onHandleStart: (_, _) {},
            ),
          ),
        ),
      );
      expect(find.byTooltip('Resize handle'), findsNothing);
      final rotate = find.byTooltip('Rotate handle');
      expect(rotate, findsOneWidget);
      final painter = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((w) => w.painter)
          .whereType<LayoutScenePainter>()
          .single;
      final bounds = selectionBounds(doc, {doc.nodes.first.id});
      final expected =
          Offset(bounds['x']! + bounds['width']! / 2, bounds['y']!) *
              painter.scale +
          painter.offset -
          const Offset(0, 24);
      expect((tester.getCenter(rotate) - expected).distance, lessThan(.01));
    },
  );

  testWidgets(
    'bus deck and row controls preserve seats and reject protected removal',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1200));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final document = busLayout(rows: 2, x: 100, y: 100);
      final root = document.nodes.first;
      final seats = document.nodes
          .where((n) => n.kind == 'seat')
          .map((n) => n.id)
          .toSet();
      final c = VenueLayoutController(document);
      addTearDown(c.dispose);
      c.select({root.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
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
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Width'), findsNothing);
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .onSelectionChanged!({2});
      await tester.pumpAndSettle();
      expect(c.document.nodes.first.assembly?['decks'], 2);
      expect(
        c.document.nodes.where((n) => n.kind == 'seat').map((n) => n.id),
        containsAll(seats),
      );
      final upper = c.document.nodes.firstWhere(
        (n) => n.kind == 'seat' && n.properties['deck'] == 1,
      );
      c.protectedSeatIds = () => {upper.id};
      final before = c.document;
      tester
          .widget<SegmentedButton<int>>(find.byType(SegmentedButton<int>))
          .onSelectionChanged!({1});
      await tester.pump();
      expect(c.document, same(before));
      expect(
        find.text(
          'Manual or protected seats prevent changing this transport layout.',
        ),
        findsOneWidget,
      );
      c.protectedSeatIds = null;
      c.undo();
      await tester.pump();
      expect(c.document.toJson(), document.toJson());
    },
  );

  testWidgets('open paths prioritize stroke controls over collapsed geometry', (
    tester,
  ) async {
    final line = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 200,
      y: 200,
      width: 160,
      height: 20,
      properties: {'shape': 'line'},
    );
    final c = VenueLayoutController(
      VenueLayoutDocument.empty().copyWith(nodes: [line]),
    );
    addTearDown(c.dispose);
    c.select({line.id});
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LayoutInspector(
            controller: c,
            cornerPivot: false,
            onPivotChanged: (_) {},
          ),
        ),
      ),
    );
    expect(find.widgetWithText(TextField, 'Outline width'), findsOneWidget);
    expect(find.text('Outline style'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Rotation °'), findsNothing);
    expect(find.widgetWithText(TextField, 'Position X'), findsNothing);
  });
}
