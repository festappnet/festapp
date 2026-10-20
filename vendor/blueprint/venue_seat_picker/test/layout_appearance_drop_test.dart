import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    VenueLayoutController c, {
    Future<void> Function()? importBackground,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(
            controller: c,
            showGallery: false,
            onImportBackground: importBackground,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
  Finder field(String label) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == label,
  );

  testWidgets(
    'palette preview exists only while pointer is inside the canvas',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      surface(tester).onDropPreview!('Table', const Offset(-100, 300));
      expect(c.document.nodes, isEmpty);
      surface(tester).onDropPreview!('Table', const Offset(400, 300));
      expect(c.document.nodes, hasLength(7));
      surface(tester).onDropPreview!('Table', const Offset(-10, 300));
      expect(c.document.nodes, isEmpty);
      surface(tester).onDrop!('Table', const Offset(-10, 300));
      expect(c.document.nodes, isEmpty);
      expect(c.canUndo, isFalse);
      surface(tester).onDrop!('Table', const Offset(400, 300));
      expect(c.document.nodes, hasLength(7));
      c.undo();
      expect(c.document.nodes, isEmpty);
      expect(c.canUndo, isFalse);
    },
  );

  testWidgets(
    'table seat styling is atomic and picker offers colors from the plan',
    (tester) async {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 300,
        width: 190,
        height: 110,
        surface: const {'type': 'rect'},
      );
      final seat = LayoutNode(
        id: newLayoutId(),
        parentId: table.id,
        kind: 'seat',
        x: 0,
        y: -90,
        width: 40,
        height: 40,
      );
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [table, seat],
        canvas: {...VenueLayoutDocument.empty().canvas, 'fill': '#123456FF'},
      );
      final c = VenueLayoutController(doc)..select({table.id});
      await open(tester, c);
      await tester.pumpAndSettle();
      tester
          .widget<SegmentedButton<String>>(find.byWidgetPredicate((w) => w is SegmentedButton<String> && w.segments.any((s) => s.value == 'children')))
          .onSelectionChanged!({'children'});
      await tester.pumpAndSettle();
      final seatField = find.byKey(const ValueKey('canonical-style-fill'));
      await tester.ensureVisible(seatField);
      await tester.tap(seatField);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('editor-color-Used colors-123456')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('editor-color-Used colors-267329')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey('editor-color-Used colors-123456')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(
        effectiveNodeProperties(c.document, c.document.nodes.last)['fill'],
        '#123456FF',
      );
      expect(c.document.nodes.last.id, seat.id);
      expect(c.document.nodes.first.childStyles['seat']['fill'], '#123456FF');
      expect(c.document.nodes.last.toJson(), seat.toJson());
      c.undo();
      expect(c.document.toJson(), doc.toJson());
    },
  );

  testWidgets(
    'canvas color and host background import are reachable in inspector',
    (tester) async {
      var imports = 0;
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(
        tester,
        c,
        importBackground: () async {
          imports++;
        },
      );
      expect(field('Background #RRGGBBAA'), findsNothing);
      await tester.tap(find.text('Canvas'));
      await tester.pumpAndSettle();
      expect(field('Background #RRGGBBAA'), findsOneWidget);
      expect(find.text('Canvas'), findsOneWidget);
      expect(find.text('Background image'), findsNothing);
      expect(find.text('Reusable objects'), findsNothing);
      expect(find.text('Fit new seats'), findsNothing);
      final upload = find.text('Upload background image');
      await tester.ensureVisible(upload);
      await tester.tap(upload);
      await tester.pumpAndSettle();
      expect(imports, 1);
      expect(c.document.nodes, isEmpty);
    },
  );
}
