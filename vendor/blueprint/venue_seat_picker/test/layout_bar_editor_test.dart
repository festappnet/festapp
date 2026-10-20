import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  test('bar stool wrong-side edit is rejected with an actionable message', () {
    final document = barLayout(count: 4);
    final c = VenueLayoutController(document);
    addTearDown(c.dispose);
    final stool = document.nodes.firstWhere((n) => n.kind == 'seat');
    expect(
      c.apply(
        document.copyWith(
          nodes: [
            for (final n in document.nodes)
              n.id == stool.id ? n.copyWith(y: -100) : n,
          ],
        ),
      ),
      false,
    );
    expect(c.error, 'Bar stools must stay on the guest side.');
    expect(c.document, same(document));
    expect(c.canUndo, false);
  });

  testWidgets(
    'grid brush follows every dragged cell and commits once on release',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      await tester.ensureVisible(find.text('Paint bar'));
      await tester.tap(find.text('Paint bar'));
      await tester.pump();
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      expect(surface().showGrid, false);
      expect(surface().gridStep, barSurfaceModuleSize);
      expect(find.text('Narrow bar modules'), findsOneWidget);
      surface().onDragStart!(const Offset(300, 600));
      await tester.pump();
      expect(surface().showGrid, true);
      expect(c.document.nodes.single.width, barSurfaceModuleSize);
      expect(c.document.nodes.single.height, barSurfaceModuleSize);
      expect(surface().gridOrigin, const Offset(270, 570));
      for (final point in [
        const Offset(300, 300),
        const Offset(700, 300),
        const Offset(700, 600),
        const Offset(700, 450),
        const Offset(850, 450),
      ]) {
        surface().onDragUpdate!(point);
        await tester.pump();
      }
      surface().onDragEnd!();
      await tester.pump();
      expect(c.document.nodes, hasLength(1));
      final bar = c.document.nodes.single;
      expect(isBarNode(bar), true);
      for (final point in [
        const Offset(300, 450),
        const Offset(500, 300),
        const Offset(800, 450),
      ]) {
        expect(hitTest(c.document, point.dx, point.dy), bar.id);
      }
      expect(hitTest(c.document, 500, 450), isNull);
      expect(validateDocument(c.document), isEmpty);
      c.undo();
      expect(c.document.nodes, isEmpty);
      expect(c.canUndo, false);
    },
  );
  testWidgets(
    'bar drops without stools and supports direct surface extrusion in one undo',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final c = VenueLayoutController(VenueLayoutDocument.empty());
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      LayoutSceneSurface surface() => tester.widget<LayoutSceneSurface>(
        find.byWidgetPredicate(
          (w) => w is LayoutSceneSurface && w.onDrop != null,
        ),
      );
      surface().onDrop!('Bar', const Offset(600, 400));
      await tester.pump();
      final inserted = c.document.nodes.singleWhere(isBarNode);
      c.apply(
        c.document.copyWith(
          nodes: [snapTableSurfaceToGrid(inserted, preset: 'rectangle')],
        ),
      );
      await tester.pump();
      final bar = c.document.nodes.singleWhere(isBarNode);
      expect(barSeatCount(c.document, bar.id), 0);
      expect(find.text('Add one seat'), findsNothing);
      expect(
        find.byTooltip('Extend surface'),
        findsNWidgets(
          (2 * (bar.width + bar.height) / (bar.surface!['moduleSize'] as num))
              .round(),
        ),
      );
      final before = c.document.toJson();
      surface().onHandleStart!(
        'Extend edge 1 cell 0',
        Offset(bar.x + bar.width / 2, bar.y),
      );
      surface().onDragUpdate!(Offset(bar.x + bar.width / 2 + 120, bar.y));
      surface().onDragEnd!();
      await tester.pump();
      expect(c.document.nodes.single.id, bar.id);
      expect(c.document.nodes.single.width, greaterThan(bar.width));
      expect(
        c.document.nodes.single.width,
        bar.width + 2 * barSurfaceModuleSize,
      );
      expect(c.document.nodes.single.height, bar.height);
      expect(
        GridSurfaceBrush.fromNode(c.document.nodes.single).cellCount,
        GridSurfaceBrush.fromNode(bar).cellCount + 2,
      );
      c.undo();
      await tester.pump();
      expect(c.document.toJson(), before);
    },
  );
}
