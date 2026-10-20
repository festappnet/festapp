import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  Future<VenueLayoutController> open(
    WidgetTester tester, {
    bool readOnly = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1440, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final doc = tableLayout(shape: 'roundedRect', count: 6).copyWith(
      canvas: {
        'x': 0,
        'y': 0,
        'width': 800,
        'height': 600,
        'fill': '#FFFFFFFF',
      },
    );
    final c = VenueLayoutController(doc)..readOnly = readOnly;
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, showGallery: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return c;
  }

  Finder canvasSurface() => find.byWidgetPredicate(
    (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
  );
  LayoutSceneSurface surface(WidgetTester tester) =>
      tester.widget<LayoutSceneSurface>(canvasSurface());

  testWidgets(
    'close button and Escape clear selection without changing history',
    (tester) async {
      final c = await open(tester);
      final ids = c.document.nodes
          .where((n) => n.kind == 'table')
          .map((n) => n.id)
          .toSet();
      final original = c.document.toJson();
      c.select(ids);
      await tester.pump();
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pump();
      expect(c.selection, isEmpty);
      expect(find.byTooltip('Clear selection'), findsNothing);
      c.select(ids);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(c.selection, isEmpty);
      expect(c.document.toJson(), original);
      expect(c.canUndo, false);
    },
  );

  testWidgets(
    'double click blank canvas reveals resize handles and editable dimensions',
    (tester) async {
      final c = await open(tester);
      final original = c.document;
      final rect = tester.getRect(canvasSurface());
      final scale = math.min((rect.width - 32) / 800, (rect.height - 32) / 600);
      final blank =
          rect.topLeft +
          Offset(
            (rect.width - 800 * scale) / 2,
            (rect.height - 600 * scale) / 2,
          ) +
          Offset(80 * scale, 80 * scale);
      await tester.tapAt(blank);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tapAt(blank);
      await tester.pumpAndSettle();
      expect(surface(tester).canvasSelected, true);
      expect(find.byTooltip('Canvas resize e handle'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Width'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Height'), findsOneWidget);
      await tester.drag(
        find.byTooltip('Canvas resize e handle'),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();
      expect(c.document.canvas['width'] as num, greaterThan(800));
      expect((c.document.canvas['width'] as num) % 1, 0);
      expect(
        c.document.nodes.map((n) => n.toJson()),
        original.nodes.map((n) => n.toJson()),
      );
      c.undo();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(surface(tester).canvasSelected, false);
    },
  );

  testWidgets(
    'canvas west and north resize retain objects and cancel restores canvas',
    (tester) async {
      final c = await open(tester);
      final original = c.document;
      surface(tester).onDoubleTapAt!(const Offset(80, 80));
      await tester.pumpAndSettle();
      surface(tester).onHandleStart!('Canvas resize nw', Offset.zero);
      surface(tester).onDragUpdate!(const Offset(799, 599));
      await tester.pump();
      expect(c.document.canvas['x'], documentBounds(original)['x']);
      expect(c.document.canvas['y'], documentBounds(original)['y']);
      expect(
        c.placementIssues.where((i) => i.code == 'outside_canvas'),
        isEmpty,
      );
      expect(
        c.document.nodes.map((n) => n.toJson()),
        original.nodes.map((n) => n.toJson()),
      );
      surface(tester).onDragCancel!();
      await tester.pumpAndSettle();
      expect(c.document.toJson(), original.toJson());
      expect(c.canUndo, false);
      surface(tester).onTap!(const Offset(400, 300));
      await tester.pumpAndSettle();
      expect(surface(tester).canvasSelected, false);
      expect(
        c.selection.single,
        original.nodes.firstWhere((n) => n.kind == 'table').id,
      );
    },
  );

  testWidgets('read-only and outside double clicks never select canvas', (
    tester,
  ) async {
    await open(tester, readOnly: true);
    expect(surface(tester).onDoubleTapAt, isNull);
    await tester.tapAt(const Offset(80, 80));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(const Offset(80, 80));
    await tester.pumpAndSettle();
    expect(surface(tester).canvasSelected, false);
    final c = await open(tester);
    surface(tester).onDoubleTapAt!(const Offset(-10, 80));
    await tester.pumpAndSettle();
    expect(surface(tester).canvasSelected, false);
    expect(c.canUndo, false);
  });
}
