import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_style.dart';

void main() {
  Finder canvas() =>
      find.byWidgetPredicate((w) => w is LayoutSceneSurface && w.onTap != null);

  test(
    'styles preserve geometry, IDs, zigzag metadata and locked descendants',
    () {
      final table = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        x: 400,
        y: 400,
        width: 190,
        height: 110,
        label: 'VIP',
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
      final locked = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        parentId: table.id,
        x: 60,
        y: -90,
        width: 40,
        height: 40,
        locked: true,
      );
      final zigzag = zigzagLine(700, 300, 1100, 300);
      final doc = VenueLayoutDocument.empty().copyWith(
        nodes: [table, seat, locked, zigzag],
      );
      final result = applyLayoutAppearance(doc, {
        table.id,
        zigzag.id,
      }, layoutAppearancePresets['Warm']!);
      expect(result.nodes.map((n) => n.id), doc.nodes.map((n) => n.id));
      expect(result.nodes[0].label, table.label);
      expect(result.nodes[0].width, table.width);
      expect(result.nodes[0].x, table.x);
      expect(
        effectiveNodeProperties(result, result.nodes[1])['fill'],
        '#D9B788FF',
      );
      expect(result.nodes[2].toJson(), locked.toJson());
      expect(result.nodes[3].properties['points'], zigzag.properties['points']);
      expect(result.nodes[3].properties['zigzagTeeth'], 8);
      expect(result.nodes[3].style['fill'], '#00000000');
      final copied = captureLayoutAppearance(result, table.id);
      expect(result.nodes[0].toJson(), table.toJson());
      expect(copied.object, captureLayoutAppearance(doc, table.id).object);
      expect(copied.seats, captureLayoutAppearance(doc, table.id).seats);
    },
  );

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

  testWidgets(
    'secondary click opens style menu; preset and copied style are undoable',
    (tester) async {
      final a = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        x: 1200,
        y: 800,
        width: 190,
        height: 110,
      );
      final b = LayoutNode(
        surface: const {'type': 'rect'},
        id: newLayoutId(),
        kind: 'table',
        x: 1600,
        y: 800,
        width: 190,
        height: 110,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [a, b]),
      );
      await open(tester, c);
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await mouse.down(tester.getCenter(canvas()));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(c.selection, {a.id});
      expect(
        find.widgetWithText(PopupMenuItem<String>, 'Style'),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'Style'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Detailed settings'));
      await tester.pumpAndSettle();
      final fill = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byKey(const ValueKey('canonical-style-fill')),
      );
      await tester.ensureVisible(fill);
      await tester.tap(fill);
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('editor-color-Basic colors-2563EB')),
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
      await tester.pumpAndSettle();
      expect(c.document.nodes.first.style['fill'], '#2563EBFF');
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Copy style'));
      await tester.tap(find.byTooltip('Copy style'));
      await tester.pump();
      c.select({b.id});
      await tester.pump();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Paste style'));
      await tester.tap(find.byTooltip('Paste style'));
      await tester.pump();
      expect(c.document.nodes.last.style['fill'], '#2563EBFF');
      expect(c.document.nodes.last.x, b.x);
      c.undo();
      expect(c.document.nodes.last.toJson(), b.toJson());
      c.undo();
      expect(c.document.nodes.first.toJson(), a.toJson());
    },
  );

  testWidgets('touch long press exposes same menu without moving object', (
    tester,
  ) async {
    final node = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      x: 1200,
      y: 800,
      width: 190,
      height: 110,
    );
    final original = VenueLayoutDocument.empty().copyWith(nodes: [node]);
    final c = VenueLayoutController(original);
    await open(tester, c);
    await tester.longPressAt(tester.getCenter(canvas()));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(PopupMenuItem<String>, 'Style'), findsOneWidget);
    expect(c.document.toJson(), original.toJson());
    expect(c.canUndo, isFalse);
  });
}
