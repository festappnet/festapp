import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/src/layout_editor/widgets/layout_inspector.dart';

void main() {
  test('each side can remove an imported fixed chair independently', () {
    final original = tableLayout(
      shape: 'rectangle',
      count: 8,
      width: 240,
      height: 96,
      edgeCounts: [4, 0, 4, 0],
    );
    final table = original.nodes.firstWhere((n) => n.kind == 'table');
    // Imported chairs can be ordered independently of their table side.
    final document = original.copyWith(
      nodes: original.nodes
          .map(
            (n) => n.kind == 'seat'
                ? n.copyWith(
                    properties: {
                      ...n.properties,
                      'slot': tableSideForSeat(original, n) == 'top' ? 10 : 0,
                    },
                  )
                : n,
          )
          .toList(),
      attachments: original.attachments
          .map(
            (a) => {
              ...a,
              'placement': {'mode': 'free'},
            },
          )
          .toList(),
    );
    final c = VenueLayoutController(document);
    addTearDown(c.dispose);
    for (final side in [0, 2]) {
      final counts = [4, 0, 4, 0]..[side] = 3;
      expect(
        c.canSetSeatCount(table.id, 7, edgeCounts: counts),
        isTrue,
        reason: 'Removing a chair on side $side must remain available',
      );
      c.setSeatCount(table.id, 7, edgeCounts: counts);
      expect(c.error, isNull);
      expect(
        c.document.nodes
            .firstWhere((n) => n.id == table.id)
            .seating['edgeCounts'],
        counts,
      );
      for (final seat in c.document.nodes.where((n) => n.kind == 'seat')) {
        final before = document.nodes.firstWhere((n) => n.id == seat.id);
        expect(
          [seat.x, seat.y, seat.rotation],
          [before.x, before.y, before.rotation],
        );
      }
      c.undo();
      expect(c.document.toJson(), document.toJson());
    }
    c.protectedSeatIds = () => document.nodes
        .where(
          (n) => n.kind == 'seat' && tableSideForSeat(document, n) == 'bottom',
        )
        .map((n) => n.id)
        .toSet();
    expect(c.canSetSeatCount(table.id, 7, edgeCounts: [4, 0, 3, 0]), isFalse);
    expect(c.canSetSeatCount(table.id, 7, edgeCounts: [3, 0, 4, 0]), isTrue);
    expect(c.document.toJson(), document.toJson());
  });

  testWidgets(
    'table edge controls reflow actual chairs and reject edge overflow',
    (tester) async {
      final original = tableLayout(
        shape: 'rectangle',
        count: 6,
        width: 240,
        height: 120,
      );
      final table = original.nodes.firstWhere((n) => n.kind == 'table');
      final c = VenueLayoutController(original)..select({table.id});
      addTearDown(c.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 280,
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
      await tester.pumpAndSettle();
      Future<void> enter(String label, String value) async {
        final field = find.widgetWithText(TextField, label);
        await tester.ensureVisible(field);
        await tester.enterText(field, value);
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
      }

      await enter('Top seats', '3');
      final preference = c.document.nodes
          .firstWhere((n) => n.id == table.id)
          .seating['edgeCounts'];
      expect(preference, [3, 1, 2, 1]);
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(7));
      expect(
        c.document.attachments.where(
          (a) =>
              a['targetId'] == table.id &&
              tableSideForSeat(
                    c.document,
                    c.document.nodes.firstWhere((n) => n.id == a['seatId']),
                  ) ==
                  'top',
        ),
        hasLength(3),
      );
      expect(
        c.document.attachments
            .where((a) => a['targetId'] == table.id)
            .every((a) => a['placement']['mode'] == 'automatic'),
        isTrue,
      );
      final before = c.document.toJson();
      await enter('Right seats', '2');
      expect(c.document.toJson(), before);
      await enter('Right seats', '0');
      expect(c.document.nodes.where((n) => n.kind == 'seat'), hasLength(6));
      expect(
        c.document.attachments.where(
          (a) =>
              a['targetId'] == table.id &&
              tableSideForSeat(
                    c.document,
                    c.document.nodes.firstWhere((n) => n.id == a['seatId']),
                  ) ==
                  'right',
        ),
        isEmpty,
      );
      c.undo();
      expect(c.document.toJson(), before);
      expect(tester.takeException(), isNull);
    },
  );
}
