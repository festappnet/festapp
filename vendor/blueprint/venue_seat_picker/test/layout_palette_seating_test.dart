import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_scene_surface.dart';

void main() {
  testWidgets(
    'palette assemblies inherit source chair dimensions and stay on top',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1440, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = VenueLayoutTemplates.create('scout-ball-182');
      final c = VenueLayoutController(source);
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VenueLayoutEditor(controller: c, showGallery: false),
          ),
        ),
      );
      for (final kind in ['Couch', 'Rows', 'Arc', 'Bus', 'Compartments']) {
        final before = c.document;
        final oldIds = before.nodes.map((n) => n.id).toSet();
        final surface = tester.widget<LayoutSceneSurface>(
          find.byWidgetPredicate(
            (w) => w is LayoutSceneSurface && w.onDrop != null,
          ),
        );
        surface.onDrop!(kind, const Offset(1600, 1600));
        await tester.pump();
        expect(c.error, isNull);
        final added = c.document.nodes
            .where((n) => !oldIds.contains(n.id))
            .toList();
        expect(added, isNotEmpty);
        final seats = added.where((n) => n.kind == 'seat');
        expect(seats, isNotEmpty);
        for (final seat in seats) {
          expect(seat.width, 77.5, reason: kind);
          expect(seat.height, 77.5, reason: kind);
        }
        final root = added.singleWhere((n) => n.parentId == null);
        final order = orderedNodes(c.document);
        expect(
          order.take(before.nodes.length).every((n) => oldIds.contains(n.id)),
          isTrue,
        );
        if (kind == 'Couch') {
          final resized = resizeCouchSeats(c.document, root.id, 3);
          expect(
            resized.nodes
                .where((n) => n.parentId == root.id)
                .every((n) => n.width == 77.5 && n.height == 77.5),
            isTrue,
          );
        }
        if (kind == 'Bus' || kind == 'Compartments') {
          final updated = kind == 'Bus'
              ? updateBusLayout(c.document, root.id, rows: 11)
              : updateCompartmentLayout(c.document, root.id, compartments: 5);
          expect(
            updated.nodes
                .where((n) => n.parentId == root.id && n.kind == 'seat')
                .every((n) => n.width == 77.5 && n.height == 77.5),
            isTrue,
          );
          expect(validateDocument(updated), isEmpty);
        }
        c.undo();
        expect(c.document.toJson(), before.toJson());
      }
    },
  );

  test(
    'controller insert raises a whole fragment while retaining child order and undo',
    () {
      final source = VenueLayoutDocument(
        nodes: [LayoutNode(id: newLayoutId(), kind: 'shape', z: 900)],
      );
      final c = VenueLayoutController(source);
      addTearDown(c.dispose);
      final fragment = tableLayout(shape: 'rect');
      c.insert(fragment);
      expect(c.error, isNull);
      expect(orderedNodes(c.document).first.id, source.nodes.single.id);
      expect(
        orderedNodes(c.document).skip(1).map((n) => n.kind),
        orderedNodes(fragment).map((n) => n.kind),
      );
      c.undo();
      expect(c.document.toJson(), source.toJson());
    },
  );
}
