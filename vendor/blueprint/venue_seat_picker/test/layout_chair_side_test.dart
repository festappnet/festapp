import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

String seatAtSide(VenueLayoutDocument d, String side) => d.nodes
    .firstWhere((n) => n.kind == 'seat' && tableSideForSeat(d, n) == side)
    .id;

void main() {
  for (final native in [false, true]) {
    testWidgets(
      'explicit chair side pins preserve identities, persist on resize and undo native=$native',
      (tester) async {
        var original = tableLayout(
          shape: 'roundedRect',
          width: 500,
          height: 100,
          count: 10,
        );
        final table = original.nodes.firstWhere((n) => n.kind == 'table');
        final right = seatAtSide(original, 'right');
        final left = seatAtSide(original, 'left');
        final ids = original.nodes
            .where((n) => n.kind == 'seat')
            .map((n) => n.id)
            .toSet();
        if (native) {
          final group = LayoutNode(
            id: newLayoutId(),
            kind: 'group',
            x: table.x,
            y: table.y,
            width: table.width,
            height: table.height,
            label: 'Native table',
          );
          original = original.copyWith(
            nodes: [
              group,
              for (final node in original.nodes)
                node.id == table.id
                    ? node.copyWith(parentId: group.id, x: 0, y: 0)
                    : node,
            ],
          );
        }
        final c = VenueLayoutController(original, protectedSeatIds: () => ids)
          ..select({right});
        addTearDown(c.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
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
        Future<void> move(String id, String label) async {
          c.select({id});
          await tester.pumpAndSettle();
          final control = find.byType(DropdownButtonFormField<String>).first;
          await tester.ensureVisible(control);
          await tester.tap(control);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await move(right, 'Top side');
        await move(left, 'Bottom side');
        String side(String id) =>
            c.document.attachments.firstWhere(
                  (a) => a['seatId'] == id,
                )['placement']['side']
                as String;
        expect(side(right), 'top');
        expect(side(left), 'bottom');
        expect(
          c.document.nodes
              .where((n) => n.kind == 'seat')
              .map((n) => n.id)
              .toSet(),
          ids,
        );
        expect(layoutCollisions(c.document), isEmpty);
        c.select({table.id});
        c.resizeObject(table.id, 600, 150);
        await tester.pumpAndSettle();
        expect(side(right), 'top');
        expect(side(left), 'bottom');
        expect(c.document.nodes.firstWhere((n) => n.id == right).y, -107);
        expect(c.document.nodes.firstWhere((n) => n.id == left).y, 107);
        c.undo();
        c.undo();
        c.undo();
        expect(c.document, same(original));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'overfull destination and locked source reject without removing chairs',
    () {
      final doc = tableLayout(
        shape: 'roundedRect',
        width: 500,
        height: 100,
        count: 10,
      );
      final seat = seatAtSide(doc, 'top');
      final bottom = seatAtSide(doc, 'bottom');
      final target = doc.nodes.firstWhere((n) => n.id == seat),
          table = doc.nodes.firstWhere((n) => n.kind == 'table');
      final pinned = setTableSeatPlacement(doc, seat, {
        'mode': 'sidePinned',
        'side': 'top',
        't': target.x / table.width + .5,
      });
      expect(
        () => setTableSeatPlacement(pinned, bottom, {
          'mode': 'sidePinned',
          'side': 'top',
          't': target.x / table.width + .5,
        }),
        throwsStateError,
      );
      final locked = doc.copyWith(
        nodes: [
          for (final n in doc.nodes)
            n.id == seat ? n.copyWith(locked: true) : n,
        ],
      );
      expect(
        () => moveTableSeatToSide(locked, seat, 'bottom'),
        throwsStateError,
      );
      expect(doc.nodes.where((n) => n.kind == 'seat').length, 10);
    },
  );

  test(
    'free manual chair keeps its position during side preference resize',
    () {
      final doc = tableLayout(
        shape: 'roundedRect',
        width: 500,
        height: 100,
        count: 10,
      );
      final right = seatAtSide(doc, 'right');
      final freeId = seatAtSide(doc, 'left');
      final free = doc.nodes
          .firstWhere((n) => n.id == freeId)
          .copyWith(x: -320, y: 100);
      final staged = doc.copyWith(
        nodes: [for (final n in doc.nodes) n.id == freeId ? free : n],
        attachments: [
          for (final a in doc.attachments)
            a['seatId'] == freeId
                ? {
                    ...a,
                    'placement': {'mode': 'free'},
                  }
                : a,
        ],
      );
      final moved = moveTableSeatToSide(staged, right, 'top');
      final table = moved.nodes.firstWhere((n) => n.kind == 'table');
      final resized = resizeNode(moved, table.id, 550, 130);
      expect(
        resized.nodes.firstWhere((n) => n.id == freeId).toJson(),
        free.toJson(),
      );
    },
  );
}
