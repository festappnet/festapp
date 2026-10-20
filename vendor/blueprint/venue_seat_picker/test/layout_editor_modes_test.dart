import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'double-click retains a selected group instead of editing its child',
    (tester) async {
      final group = LayoutNode(id: newLayoutId(), kind: 'group', x: 0, y: 0);
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        x: 200,
        y: 200,
        width: 160,
        height: 100,
        surface: const {'type': 'rect'},
      );
      final c = VenueLayoutController(
        VenueLayoutDocument(nodes: [group, table]),
      )..select({group.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.pumpAndSettle();
      tester
          .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
          .onDoubleTapAt!(const Offset(250, 240));
      await tester.pumpAndSettle();
      expect(c.selection, {group.id});
      expect(c.canUndo, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewing cannot edit geometry and explicit editing retains the draft',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final seat = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 200,
        y: 200,
        width: 32,
        height: 32,
        label: 'A1',
      );
      final floor = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 300,
        y: 300,
        width: 600,
        height: 600,
        label: 'Floor',
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          nodes: [floor, seat],
          canvas: {
            'x': 0,
            'y': 0,
            'width': 600,
            'height': 600,
            'fill': '#FFFFFFFF',
          },
        ),
      );
      final activated = <String>[];
      addTearDown(c.dispose);
      var editing = false;
      late StateSetter setHostState;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return VenueLayoutEditor(
                  controller: c,
                  interactionEnabled: editing,
                  onNodeActivated: activated.add,
                  inspectorBuilder: (_, node) => Text('Details: ${node.label}'),
                );
              },
            ),
          ),
        ),
      );
      LayoutSceneSurface surface() =>
          tester.widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface));
      final surfaceState = tester.state(find.byType(LayoutSceneSurface));
      final initial = c.document;
      expect(find.byKey(const ValueKey('layout-palette')), findsNothing);
      expect(find.byTooltip('Undo'), findsNothing);
      expect(find.byTooltip('Resize'), findsNothing);
      expect(find.byKey(const ValueKey('edit-canvas')), findsNothing);
      expect(surface().onDragStart, isNull);
      expect(surface().onHandleStart, isNull);
      expect(surface().onDoubleTapAt, isNull);
      surface().onTap!(const Offset(200, 200));
      await tester.pump();
      expect(find.text('Details: A1'), findsOneWidget);
      expect(activated, [seat.id]);
      surface().onTap!(const Offset(500, 500));
      await tester.pump();
      expect(c.selection, isEmpty);
      expect(surface().selected, isEmpty);
      expect(find.text('Details: Floor'), findsNothing);
      expect(activated, [seat.id]);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.selection, {seat.id});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(c.selection, {seat.id});
      surface().onTap!(const Offset(700, 700));
      await tester.pump();
      expect(c.selection, isEmpty);
      expect(activated, [seat.id]);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.drag(find.byType(LayoutSceneSurface), const Offset(50, 20));
      await tester.pumpAndSettle();
      expect(c.document, same(initial));
      expect(c.dirty, isFalse);

      setHostState(() => editing = true);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(LayoutSceneSurface)), same(surfaceState));
      expect(find.byKey(const ValueKey('layout-palette')), findsOneWidget);
      expect(surface().onDragStart, isNotNull);
      c.updateNode(seat.copyWith(x: 240));
      await tester.pump();
      final draft = c.document;
      await tester.tap(find.byTooltip('Pan'));
      setHostState(() => editing = false);
      await tester.pumpAndSettle();
      expect(surface().onHandleStart, isNull);
      expect(find.byTooltip('Resize'), findsNothing);
      expect(find.text('Unsaved changes'), findsOneWidget);
      expect(c.document, same(draft));
      expect(tester.state(find.byType(LayoutSceneSurface)), same(surfaceState));
      setHostState(() => editing = true);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.near_me_outlined),
            )
            .isSelected,
        isTrue,
      );
      c.markSaved();
      await tester.pump();
      expect(find.byKey(const ValueKey('layout-palette')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an empty viewer never opens the template gallery', (
    tester,
  ) async {
    final c = VenueLayoutController(VenueLayoutDocument.empty());
    addTearDown(c.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VenueLayoutEditor(controller: c, interactionEnabled: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(c.document.nodes, isEmpty);
    expect(c.dirty, isFalse);
  });
}
