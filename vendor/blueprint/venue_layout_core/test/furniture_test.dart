import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<LayoutNode> cushions(VenueLayoutDocument d) =>
    d.nodes.where((n) => n.kind == 'seat').toList();

void main() {
  test(
    'canonical couch preserves typed footprint, seat identities and independent placement intent',
    () {
      var d = couchLayout(count: 2);
      final root = d.nodes.first, seat = cushions(d).first;
      expect(validateDocument(d), isEmpty);
      expect(root.assembly!['kind'], 'couch');
      expect(root.assembly!['seats'], 2);
      expect(root.properties.containsKey('fill'), isFalse);
      final minimumWidth = root.assembly!['minSeatWidth'];
      d = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            n.id == seat.id ? n.copyWith(x: seat.x + 7, rotation: 37) : n,
        ],
        attachments: [
          for (final a in d.attachments)
            a['seatId'] == seat.id
                ? {
                    ...a,
                    'placement': {'mode': 'free'},
                    'rotationMode': 'manual',
                  }
                : a,
        ],
      );
      final pose = d.nodes.firstWhere((n) => n.id == seat.id);
      final resized = resizeCouchSeats(d, root.id, 3);
      expect(validateDocument(resized), isEmpty);
      expect(resized.nodes.first.assembly!['seats'], 3);
      expect(resized.nodes.first.assembly!['minSeatWidth'], minimumWidth);
      expect(resized.nodes.first.properties.containsKey('seatWidth'), isFalse);
      final after = resized.nodes.firstWhere((n) => n.id == seat.id);
      expect(
        [after.x, after.y, after.rotation],
        [pose.x, pose.y, pose.rotation],
      );
      expect(resized.attachments.length, 3);
      expect(
        (resized.selectionUnits.single['nodeIds'] as List).toSet(),
        containsAll(cushions(d).map((n) => n.id)),
      );
      expect(
        () =>
            resizeCouchSeats(resized, root.id, 4, protectedSeatIds: {seat.id}),
        throwsA(isA<CouchResizeRejected>()),
      );
    },
  );

  test('couch materializes empty-label furniture and one atomic unit', () {
    final d = couchLayout();
    final root = d.nodes.first;
    expect(root.label, isEmpty);
    expect(couchSeatCount(d, root.id), 2);
    expect(d.selectionUnits.single['nodeIds'], cushions(d).map((n) => n.id));
    expect(d.selectionUnits.single['kind'], 'atomic');
    expect(validateDocument(d), isEmpty);
    expect(layoutCollisions(d), isEmpty);
    expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
  });

  test('free count changes retain stable IDs and atomic identity', () {
    final d = couchLayout(width: 100);
    final root = d.nodes.first;
    final original = cushions(d);
    final expanded = resizeCouchSeats(d, root.id, 5);
    expect(
      cushions(expanded).take(2).map((n) => n.id),
      original.map((n) => n.id),
    );
    expect(expanded.selectionUnits.single['id'], d.selectionUnits.single['id']);
    expect(expanded.nodes.first.width, 226);
    expect(expanded.canvas, d.canvas);
    expect(layoutCollisions(expanded), isEmpty);
    final shrunk = resizeCouchSeats(expanded, root.id, 1);
    expect(cushions(shrunk).single.id, original.first.id);
    expect(shrunk.selectionUnits.single['id'], d.selectionUnits.single['id']);
    expect(shrunk.selectionUnits.single['nodeIds'], [original.first.id]);
    expect(validateDocument(shrunk), isEmpty);
  });

  test(
    'count changes preserve cushion dimensions and reverse body growth for custom rotated couches',
    () {
      for (final initial in [
        couchLayout(),
        couchLayout(count: 3, width: 300, height: 120),
      ]) {
        final root = initial.nodes.first.copyWith(rotation: 31);
        final d = initial.copyWith(nodes: [root, ...initial.nodes.skip(1)]);
        final count = couchSeatCount(d, root.id);
        final originalWidth = cushions(d).first.width;
        final expanded = resizeCouchSeats(d, root.id, count + 2);
        expect(expanded.nodes.first.width, greaterThan(root.width));
        final restored = resizeCouchSeats(expanded, root.id, count);
        expect(restored.nodes.first.width, closeTo(root.width, 1e-8));
        expect(
          cushions(restored).map((n) => n.id),
          cushions(d).map((n) => n.id),
        );
        final smaller = resizeCouchSeats(d, root.id, count - 1);
        expect(smaller.nodes.first.width, lessThan(root.width));
        for (final candidate in [expanded, restored, smaller]) {
          expect(candidate.nodes.first.x, root.x);
          expect(candidate.nodes.first.y, root.y);
          expect(candidate.nodes.first.rotation, 31);
          expect(candidate.nodes.first.height, root.height);
          expect(candidate.canvas, d.canvas);
          expect(
            candidate.selectionUnits.single['id'],
            d.selectionUnits.single['id'],
          );
          expect(
            cushions(
              candidate,
            ).every((n) => (n.width - originalWidth).abs() < 1e-8),
            true,
          );
          expect(layoutCollisions(candidate), isEmpty);
        }
      }
    },
  );

  test(
    'any protected atomic member rejects all count changes without mutation',
    () {
      final d = couchLayout();
      final before = d.toJson();
      for (final count in [1, 3]) {
        expect(
          () => resizeCouchSeats(
            d,
            d.nodes.first.id,
            count,
            protectedSeatIds: {cushions(d).last.id},
          ),
          throwsA(
            isA<CouchResizeRejected>().having(
              (e) => e.message,
              'message',
              'Reserved or blocked seats prevent changing this couch.',
            ),
          ),
        );
      }
      expect(d.toJson(), before);
      expect(
        identical(
          resizeCouchSeats(
            d,
            d.nodes.first.id,
            2,
            protectedSeatIds: {cushions(d).last.id},
          ),
          d,
        ),
        isTrue,
      );
    },
  );

  test(
    'body resize recomputes cushions, clamps minima and preserves metadata',
    () {
      var d = couchLayout();
      final root = d.nodes.first;
      final seat = cushions(d).first;
      d = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            if (n.id == root.id)
              n.copyWith(rotation: 37, label: 'Existing couch')
            else if (n.id == seat.id)
              n.copyWith(
                properties: {...n.properties},
                style: {'fill': '#123456FF'},
              )
            else
              n,
        ],
      );
      final resized = resizeCouchBody(
        d,
        root.id,
        240,
        80,
        protectedSeatIds: {seat.id},
      );
      expect(resized.nodes.first.rotation, 37);
      expect(resized.nodes.first.label, 'Existing couch');
      expect(resized.nodes.first.x, root.x);
      expect(cushions(resized).first.width, 104);
      expect(cushions(resized).first.height, 64);
      expect(cushions(resized).first.y, 6);
      expect(cushions(resized).first.style['fill'], '#123456FF');
      expect(cushions(resized).map((n) => n.id), cushions(d).map((n) => n.id));
      final small = resizeCouchBody(d, root.id, 1, 1);
      expect(small.nodes.first.width, root.width);
      expect(small.nodes.first.height, root.height);
      expect(cushions(small).first.width, seat.width);
      expect(cushions(small).first.height, seat.height);
    },
  );

  test(
    'legacy couch slots inferred left-to-right and locked members reject',
    () {
      final d = couchLayout();
      final root = d.nodes.first;
      final legacy = d.copyWith(
        nodes: d.nodes.reversed
            .map(
              (n) => n.kind == 'seat'
                  ? n.copyWith(properties: {...n.properties}..remove('slot'))
                  : n,
            )
            .toList(),
      );
      final resized = resizeCouchSeats(legacy, root.id, 3);
      expect(cushions(resized).first.id, cushions(d).first.id);
      for (final locked in [root.id, cushions(d).last.id]) {
        final lockedDocument = d.copyWith(
          nodes: [
            for (final n in d.nodes)
              n.id == locked ? n.copyWith(locked: true) : n,
          ],
        );
        expect(
          () => resizeCouchSeats(lockedDocument, root.id, 1),
          throwsStateError,
        );
        expect(
          () => resizeCouchBody(lockedDocument, root.id, 240, 120),
          throwsStateError,
        );
      }
    },
  );

  test('invalid count and dimensions fail atomically', () {
    final d = couchLayout();
    expect(() => resizeCouchSeats(d, d.nodes.first.id, 0), throwsRangeError);
    expect(
      () => resizeCouchBody(d, d.nodes.first.id, double.nan, 100),
      throwsArgumentError,
    );
    expect(
      () => resizeCouchBody(d, d.nodes.first.id, 100, double.infinity),
      throwsArgumentError,
    );
  });
}
