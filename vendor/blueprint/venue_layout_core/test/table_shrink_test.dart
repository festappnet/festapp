import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final shape in ['rect', 'circle']) {
    test(
      '$shape shrink removes only surplus free seats and keeps retained identities/styles',
      () {
        final original = tableLayout(
              shape: shape,
              count: 8,
              width: 240,
              height: 160,
            ),
            table = original.nodes.first;
        final decorated = original.copyWith(
          nodes: original.nodes
              .map(
                (n) => n.kind == 'seat'
                    ? n.copyWith(
                        properties: {...n.properties},
                        style: {'fill': '#123456FF'},
                      )
                    : n,
              )
              .toList(),
        );
        final result = resizeNode(
              decorated,
              table.id,
              120,
              shape == 'circle' ? 120 : 100,
            ),
            capacity = tableCapacity(
              result.nodes.firstWhere((n) => n.id == table.id),
            );
        final seats = result.nodes.where((n) => n.kind == 'seat').toList(),
            oldIds = original.nodes
                .where((n) => n.kind == 'seat')
                .map((n) => n.id)
                .toSet();
        expect(seats.length, capacity);
        expect(seats.length, lessThan(8));
        expect(seats.every((n) => oldIds.contains(n.id)), isTrue);
        expect(
          seats.every(
            (n) =>
                n.width == 40 &&
                n.height == 40 &&
                n.style['fill'] == '#123456FF',
          ),
          isTrue,
        );
        expect(result.attachments.length, seats.length);
        expect(
          result.attachments.every(
            (a) => seats.any((n) => n.id == a['seatId']),
          ),
          isTrue,
        );
        expect(validateDocument(result), isEmpty);
        expect(original.nodes.where((n) => n.kind == 'seat').length, 8);
        expect(original.nodes.first.width, 240);
      },
    );
    test(
      '$shape booked trailing seats survive while enough free chairs are removed',
      () {
        final original = tableLayout(
              shape: shape,
              count: 8,
              width: 240,
              height: 160,
            ),
            table = original.nodes.first,
            seats = original.nodes.where((n) => n.kind == 'seat').toList(),
            protected = {seats.last.id, seats[seats.length - 2].id};
        final result = resizeNode(
              original,
              table.id,
              120,
              shape == 'circle' ? 120 : 100,
              protectedSeatIds: protected,
            ),
            retained = result.nodes
                .where((n) => n.kind == 'seat')
                .map((n) => n.id)
                .toSet();
        expect(retained.containsAll(protected), isTrue);
        expect(validateDocument(result), isEmpty);
        expect(original.nodes.where((n) => n.kind == 'seat').length, 8);
      },
    );
    test(
      '$shape insufficient free seats rejects all changes with stable typed error',
      () {
        final original = tableLayout(
              shape: shape,
              count: 8,
              width: 240,
              height: 160,
            ),
            table = original.nodes.first,
            seats = original.nodes.where((n) => n.kind == 'seat').toList(),
            before = original.toJson();
        expect(
          () => resizeNode(
            original,
            table.id,
            120,
            shape == 'circle' ? 120 : 100,
            protectedSeatIds: seats.map((n) => n.id).toSet(),
          ),
          throwsA(
            isA<TableResizeRejected>()
                .having((e) => e.tableId, 'tableId', table.id)
                .having(
                  (e) => e.message,
                  'message',
                  'Reserved or blocked seats prevent shrinking this table.',
                ),
          ),
        );
        expect(original.toJson(), before);
      },
    );
  }
  test(
    'locked table/ancestor/chair cannot be removed or partially resized',
    () {
      final original = tableLayout(shape: 'roundedRect', count: 6),
          table = original.nodes.first,
          seats = original.nodes.where((n) => n.kind == 'seat').toList();
      for (final id in [table.id, seats.last.id]) {
        final locked = original.copyWith(
          nodes: original.nodes
              .map((n) => n.id == id ? n.copyWith(locked: true) : n)
              .toList(),
        );
        expect(() => resizeNode(locked, table.id, 100, 100), throwsStateError);
        expect(locked.nodes.length, original.nodes.length);
      }
      final locked = original.copyWith(
        nodes: original.nodes
            .map((n) => n.id == seats.last.id ? n.copyWith(locked: true) : n)
            .toList(),
      );
      expect(
        () => reflowTable(locked, table.id, 0),
        throwsA(isA<TableResizeRejected>()),
      );
    },
  );
  test(
    'shrinking cleans relations but preserves independent preset snapshots and atomic membership',
    () {
      final original = tableLayout(
            shape: 'roundedRect',
            count: 8,
            width: 240,
            height: 160,
          ),
          table = original.nodes.first,
          seats = original.nodes.where((n) => n.kind == 'seat').toList();
      var document = original.copyWith(
        selectionUnits: [
          {
            'id': newLayoutId(),
            'kind': 'atomic',
            'nodeIds': [seats[6].id, seats[7].id],
          },
        ],
      );
      document = savePreset(document, {table.id}, 'Original table');
      final result = resizeNode(document, table.id, 120, 100),
          remaining = result.nodes
              .where((n) => n.kind == 'seat')
              .map((n) => n.id)
              .toSet();
      expect(remaining.length, lessThan(8));
      expect(remaining.contains(seats[6].id), remaining.contains(seats[7].id));
      expect(result.presets, document.presets);
      expect(validateDocument(result), isEmpty);
    },
  );
  test(
    'explicit count reduction protects reservation IDs without persisting their status',
    () {
      final document = tableLayout(
            shape: 'ellipse',
            count: 8,
            width: 240,
            height: 160,
          ),
          table = document.nodes.first,
          last = document.nodes.last;
      final result = reflowTable(
        document,
        table.id,
        3,
        protectedSeatIds: {last.id},
      );
      expect(result.nodes.any((n) => n.id == last.id), isTrue);
      expect(result.nodes.where((n) => n.kind == 'seat').length, 3);
      expect(result.toJson().toString().contains('protectedSeatIds'), isFalse);
      expect(validateDocument(result), isEmpty);
    },
  );
  test('free manual surplus may be removed, enlarging does not add seats', () {
    var d = tableLayout(shape: 'roundedRect', count: 6), table = d.nodes.first;
    d = d.copyWith(
      nodes: d.nodes
          .map(
            (n) => n.kind == 'seat'
                ? n.copyWith(properties: {...n.properties, 'manual': true})
                : n,
          )
          .toList(),
    );
    final result = resizeNode(d, table.id, 64, 64);
    expect(result.nodes.where((n) => n.kind == 'seat'), isEmpty);
    expect(result.attachments, isEmpty);
    expect(validateDocument(result), isEmpty);
    final expanded = resizeNode(
      tableLayout(shape: 'roundedRect', count: 6, id: table.id),
      table.id,
      500,
      400,
    );
    expect(expanded.nodes.where((n) => n.kind == 'seat').length, 6);
  });
}
