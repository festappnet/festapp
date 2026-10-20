import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'business names stay outside geometry editing while text remains editable',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'T1',
        x: 100,
        y: 100,
        surface: const {'type': 'rect'},
      );
      final text = LayoutNode(
        id: newLayoutId(),
        kind: 'text',
        label: 'Entrance',
        properties: {'text': 'Entrance'},
        x: 300,
        y: 100,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [table, text]),
      );
      addTearDown(c.dispose);
      c.select({table.id});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(
              controller: c,
              readOnlyLabelNodeIds: {table.id},
            ),
          ),
        ),
      );
      Finder name() => find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == 'Name',
      );
      expect(name(), findsNothing);
      tester
          .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
          .onDoubleTapAt!(const Offset(100, 100));
      await tester.pump();
      expect(find.byKey(const ValueKey('layout-inline-label')), findsNothing);
      c.select({text.id});
      await tester.pump();
      expect(name(), findsOneWidget);
      tester
          .widget<LayoutSceneSurface>(find.byType(LayoutSceneSurface))
          .onDoubleTapAt!(const Offset(300, 100));
      await tester.pump();
      expect(find.byKey(const ValueKey('layout-inline-label')), findsOneWidget);
      expect(c.dirty, isFalse);
    },
  );

  testWidgets(
    'controlled table selection supports bulk viewing without geometry edits',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final group = LayoutNode(
        id: newLayoutId(),
        kind: 'group',
        label: 'Commercial T1',
      );
      final table1 = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        parentId: group.id,
        label: 'T1',
        x: 100,
        y: 100,
        width: 80,
        height: 60,
        surface: const {'type': 'rect'},
      );
      final table2 = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        label: 'T2',
        x: 300,
        y: 100,
        width: 80,
        height: 60,
        surface: const {'type': 'rect'},
      );
      final floor = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        z: -1,
        x: 250,
        y: 250,
        width: 500,
        height: 500,
      );
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(
          nodes: [floor, group, table1, table2],
        ),
      );
      addTearDown(c.dispose);
      c.select({floor.id});
      final original = c.document;
      var selected = <String>{};
      final activated = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (_, setState) => VenueLayoutEditor(
                controller: c,
                interactionEnabled: false,
                viewSelection: selected,
                viewSelectableIds: {group.id, table1.id, table2.id},
                viewSelectionTarget: (id) => id == table1.id ? group.id : id,
                onViewSelectionChanged: (ids) => setState(() => selected = ids),
                onNodeActivated: activated.add,
                inspectorOverride: const Text('Standing areas and tables'),
              ),
            ),
          ),
        ),
      );
      LayoutSceneSurface surface() =>
          tester.widget(find.byType(LayoutSceneSurface));
      expect(find.text('Standing areas and tables'), findsOneWidget);
      await tester.tap(find.byTooltip('Pan'));
      await tester.pump();
      expect(surface().onTap, isNull);
      expect(c.document, same(original));
      await tester.tap(find.byTooltip('Select'));
      await tester.pump();
      expect(surface().onTap, isNotNull);

      final region = find
          .descendant(
            of: find.byKey(const ValueKey('layout-map-gesture-surface')),
            matching: find.byType(MouseRegion),
          )
          .first;
      expect(
        tester.widget<MouseRegion>(region).cursor,
        SystemMouseCursors.basic,
      );

      surface().onTap!(const Offset(100, 100));
      await tester.pump();
      expect(selected, {group.id});
      expect(surface().selected, selected);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      surface().onTap!(const Offset(300, 100));
      await tester.pump();
      expect(selected, {group.id, table2.id});
      surface().onTap!(const Offset(100, 100));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(selected, {table2.id});
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(activated.last, table2.id);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(selected, {group.id});
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(selected, {
        table2.id,
      }, reason: 'A physical table alias must not trap keyboard navigation');
      surface().onTap!(const Offset(450, 450));
      await tester.pump();
      expect(selected, isEmpty);
      expect(c.selection, {floor.id});
      expect(c.document, same(original));
      expect(c.dirty, isFalse);
      expect(surface().onHandleStart, isNull);
    },
  );

  testWidgets('hover tooltip is opaque and follows light and dark themes', (
    tester,
  ) async {
    final seat = LayoutNode(
      id: newLayoutId(),
      kind: 'seat',
      x: 100,
      y: 100,
      width: 40,
      height: 40,
    );
    final document = VenueLayoutDocument.empty().copyWith(
      nodes: [seat],
      canvas: {
        'x': 0,
        'y': 0,
        'width': 200,
        'height': 200,
        'fill': '#FFFFFFFF',
      },
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    for (final brightness in Brightness.values) {
      final theme = ThemeData(brightness: brightness);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 400,
                child: LayoutSceneSurface(
                  document: document,
                  showControls: false,
                  presentation: {
                    seat.id: {'tooltip': 'T1 - 250 CZK'},
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await mouse.moveTo(tester.getCenter(find.byType(LayoutSceneSurface)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      final tooltip = tester.widget<Tooltip>(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'T1 - 250 CZK',
        ),
      );
      final decoration = tooltip.decoration! as BoxDecoration;
      expect(decoration.color!.a, 1);
      expect(
        decoration.color,
        theme.colorScheme.surfaceContainerHigh.withAlpha(255),
      );
      expect(tooltip.textStyle!.color, theme.colorScheme.onSurface);
      await mouse.moveTo(Offset.zero);
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
    'all floor patterns remain visible at overview scale in both brightnesses',
    (tester) async {
      await tester.runAsync(() async {
        for (final background in ['#FFFFFFFF', '#171717FF']) {
          for (final style in ['wood', 'tile', 'carpet']) {
            final doc = VenueLayoutDocument.empty().copyWith(
              canvas: {
                'x': 0,
                'y': 0,
                'width': 1000,
                'height': 1000,
                'fill': background,
                'floorStyle': style,
              },
            );
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder);
            LayoutScenePainter(
              scene: compileScene(doc),
              resources: const {},
              selected: const {},
              scale: .2,
              offset: Offset.zero,
              canvasColor: Colors.white,
              selectionColor: Colors.blue,
            ).paint(canvas, const Size(200, 200));
            final picture = recorder.endRecording();
            final image = await picture.toImage(200, 200);
            final data = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final base = background == '#FFFFFFFF' ? 255 : 23;
            var visible = 0;
            for (var i = 0; i < data.lengthInBytes; i += 4) {
              if ((data.getUint8(i) - base).abs() >= 20) visible++;
            }
            expect(
              visible,
              greaterThan(100),
              reason:
                  '$style must remain recognizable on $background at 20% zoom',
            );
            image.dispose();
            picture.dispose();
          }
        }
      });
    },
  );
}
