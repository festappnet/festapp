import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
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
  Future<void> tool(WidgetTester tester, String name) async {
    await tester.enterText(find.byType(TextField).first, name);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is Draggable<String> && w.data == name),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'canonical palette inserts every ordinary object without legacy style aliases',
    (tester) async {
      final c = VenueLayoutController(
        VenueLayoutDocument(
          schemaVersion: 2,
          canvas: {
            'x': 0,
            'y': 0,
            'width': 6000,
            'height': 4000,
            'fill': '#FFFFFFFF',
          },
        ),
      );
      await open(tester, c);
      for (final name in [
        'Table',
        'Round table',
        'Bar',
        'Couch',
        'Rows',
        'Arc',
        'Compartments',
        'Bus',
        'Double-decker bus',
        'Seat',
        'Standing',
        'Rectangle',
        'Ellipse',
        'Line',
        'Arrow',
        'Polygon',
        'Polyline',
        'Draw table',
        'Draw bar',
      ]) {
        surface(tester).onDrop!(name, const Offset(1500, 1200));
        await tester.pumpAndSettle();
        expect(c.error, isNull, reason: name);
        expect(c.document.nodes, isNotEmpty, reason: name);
        expect(validateDocument(c.document), isEmpty, reason: name);
        expect(c.document.schemaVersion, 2);
        expect(
          c.document.nodes.every(
            (node) =>
                !node.properties.containsKey('fill') &&
                !node.properties.containsKey('size') &&
                !node.properties.containsKey('fontId'),
          ),
          isTrue,
          reason: name,
        );
        c.undo();
        await tester.pumpAndSettle();
        expect(c.document.nodes, isEmpty, reason: name);
      }
      surface(tester).onDrop!('Text', const Offset(1500, 1200));
      await tester.pumpAndSettle();
      expect(c.error, isNull);
      expect(validateDocument(c.document), isEmpty);
      expect(c.document.nodes.single.style['label']['size'], 24);
    },
  );

  testWidgets(
    'couch count controls and resize retain identities and protect atomic membership',
    (tester) async {
      final original = couchLayout();
      final couch = original.nodes.firstWhere((n) => n.kind == 'furniture');
      final protected = <String>{};
      final c = VenueLayoutController(
        original,
        protectedSeatIds: () => protected,
      )..select({couch.id});
      await open(tester, c);
      expect(find.widgetWithText(TextField, 'Seats on couch'), findsOneWidget);
      await tester.tap(find.byTooltip('Add one seat'));
      await tester.pump();
      expect(couchSeatCount(c.document, couch.id), 3);
      final wider = c.document.nodes.firstWhere((n) => n.id == couch.id).width;
      expect(wider, greaterThan(couch.width));
      await tester.tap(find.byTooltip('Remove one seat'));
      await tester.pump();
      expect(couchSeatCount(c.document, couch.id), 2);
      expect(
        c.document.nodes.firstWhere((n) => n.id == couch.id).width,
        couch.width,
      );
      c.undo();
      await tester.pump();
      expect(couchSeatCount(c.document, couch.id), 3);
      expect(c.document.nodes.firstWhere((n) => n.id == couch.id).width, wider);
      final unitId = original.selectionUnits.single['id'];
      expect(c.document.selectionUnits.single['id'], unitId);
      for (final seat in original.nodes.where((n) => n.kind == 'seat')) {
        expect(c.document.nodes.any((n) => n.id == seat.id), true);
      }
      expect(c.resizeObject(couch.id, 240, 120), true);
      final seats = c.document.nodes.where((n) => n.kind == 'seat').toList();
      expect(seats.map((n) => n.width).toSet().length, 1);
      expect(seats.first.height, 84);
      c.undo();
      protected.add(seats.first.id);
      c.setSeatCount(couch.id, 2);
      expect(couchSeatCount(c.document, couch.id), 3);
      expect(c.error, 'Reserved or blocked seats prevent changing this couch.');
      c.undo();
      expect(
        couchSeatCount(c.document, couch.id),
        3,
        reason:
            'History must not change a sold atomic unit, even when the protected ID survives.',
      );
      protected.clear();
      c.undo();
      expect(c.document.toJson(), original.toJson());
    },
  );

  testWidgets(
    'two-click straight line previews and endpoint drag is one undo',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      await tool(tester, 'Line');
      final canvas = find.byWidgetPredicate(
        (w) => w is LayoutSceneSurface && w.onViewportScaleChanged != null,
      );
      final before = tester.getRect(canvas);
      surface(tester).onPointTap!(const Offset(320, 320));
      await tester.pump();
      expect(surface(tester).pathPoints, [const Offset(320, 320)]);
      expect(tester.getRect(canvas), before);
      surface(tester).onHover!(const Offset(560, 320));
      expect(c.document.nodes.single.properties['shape'], 'line');
      surface(tester).onPointTap!(const Offset(560, 320));
      await tester.pumpAndSettle();
      final line = c.document.nodes.single;
      expect(line.properties['shape'], 'line');
      expect(c.selection, {line.id});
      expect(find.byTooltip('Add bend'), findsNothing);
      surface(tester).onHandleStart!('Vertex 1', const Offset(560, 320));
      surface(tester).onDragUpdate!(const Offset(560, 400));
      surface(tester).onDragEnd!();
      final moved = c.document.nodes.single;
      expect(moved.id, line.id);
      expect(moved.properties['shape'], 'line');
      expect(moved.properties['points'], hasLength(2));
      c.undo();
      expect(c.document.nodes.single.toJson(), line.toJson());
      c.undo();
      expect(c.document.nodes, isEmpty);
    },
  );

  testWidgets(
    'zigzag uses two endpoints and exposes pattern controls with one undo',
    (tester) async {
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      await open(tester, c);
      await tool(tester, 'Polyline');
      surface(tester).onPointTap!(const Offset(320, 320));
      await tester.pump();
      surface(tester).onHover!(const Offset(640, 320));
      expect(isZigzagNode(c.document.nodes.single), isTrue);
      expect(c.document.nodes.single.properties['points'], hasLength(18));
      surface(tester).onPointTap!(const Offset(640, 320));
      await tester.pumpAndSettle();
      final original = c.document.nodes.single;
      expect(c.selection, {original.id});
      expect(surface(tester).pathPoints, isEmpty);
      expect(find.text('Number of teeth'), findsOneWidget);
      expect(find.text('Zigzag height'), findsOneWidget);
      expect(find.byTooltip('Add bend'), findsNothing);
      expect(find.byTooltip('Line endpoint handle'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Add one tooth'));
      await tester.pump();
      expect(c.document.nodes.single.properties['zigzagTeeth'], 9);
      expect(c.document.nodes.single.properties['points'], hasLength(20));
      expect(c.document.nodes.single.id, original.id);
      await tester.tap(find.byTooltip('Remove one tooth'));
      await tester.pump();
      expect(c.document.nodes.single.toJson(), original.toJson());
      c.undo();
      expect(c.document.nodes.single.properties['zigzagTeeth'], 9);
      c.undo();
      expect(c.document.nodes.single.toJson(), original.toJson());
      await tester.pump();
      surface(tester).onHandleStart!(
        'Zigzag amplitude',
        const Offset(480, 332),
      );
      surface(tester).onDragUpdate!(const Offset(480, 344));
      surface(tester).onDragEnd!();
      expect(c.document.nodes.single.properties['zigzagAmplitude'], 24);
      expect(c.document.nodes.single.id, original.id);
      c.undo();
      expect(c.document.nodes.single.toJson(), original.toJson());
      c.undo();
      expect(c.document.nodes, isEmpty);
    },
  );
  testWidgets('Shift snaps straight and zigzag endpoint angles', (
    tester,
  ) async {
    for (final zigzag in [false, true]) {
      final node = zigzag
          ? zigzagLine(320, 320, 640, 320)
          : shapeFromPoints('line', [
              [320, 320],
              [640, 320],
            ]);
      final c = VenueLayoutController(
        VenueLayoutDocument.empty().copyWith(nodes: [node]),
      )..select({node.id});
      await open(tester, c);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      final last = (node.properties['points'] as List).length - 1;
      surface(tester).onHandleStart!(
        zigzag ? 'Zigzag endpoint $last' : 'Vertex $last',
        const Offset(640, 320),
      );
      surface(tester).onDragUpdate!(const Offset(600, 400));
      surface(tester).onDragEnd!();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final edited = c.document.nodes.single;
      final points = edited.properties['points'] as List;
      final matrix = worldMatrix(c.document, edited);
      final start = transformPoint(
        matrix,
        (points.first[0] as num).toDouble(),
        (points.first[1] as num).toDouble(),
      );
      final end = transformPoint(
        matrix,
        (points.last[0] as num).toDouble(),
        (points.last[1] as num).toDouble(),
      );
      expect(start[0], closeTo(320, .01));
      expect(start[1], closeTo(320, .01));
      expect(
        math.atan2(end[1] - start[1], end[0] - start[0]) * 180 / math.pi,
        closeTo(15, .01),
      );
      c.undo();
      expect(c.document.nodes.single.toJson(), node.toJson());
    }
  });
}
