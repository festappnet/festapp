import 'support/style.dart';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

Map item(
  VenueLayoutDocument d,
  String id, {
  Map<String, dynamic> presentation = const {},
}) =>
    (compileScene(d, presentation: presentation)['items'] as List).singleWhere(
          (i) => i['id'] == id,
        )
        as Map;
VenueLayoutDocument family(VenueLayoutDocument d, String name) => d.copyWith(
  styles: {
    'kinds': {
      for (final kind in layoutAppearanceKinds)
        kind: {
          if (kind != 'text') 'material': name,
          if (kind == 'seat')
            'seatStyle': name == 'wood'
                ? 'wood'
                : name == 'lounge'
                ? 'upholstered'
                : 'plain',
        },
    },
  },
);
void main() {
  test(
    'three families have distinct actual chair silhouettes and exact outline hit paths',
    () {
      final n = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 200,
        y: 200,
        width: 60,
        height: 60,
      );
      final base = VenueLayoutDocument(nodes: [n]);
      final paths = <String, dynamic>{};
      for (final style in layoutObjectStyles) {
        final d = family(base, style), body = item(d, n.id);
        paths[style] = body['path'];
        expect(body['hitPath'], body['path']);
        expect(d.nodes.single, same(n));
        expect(d.canvas, base.canvas);
        expect(LayoutSpatialIndex(d).hitTest(200, 200), n.id);
        // Empty corners of the styled chair must not remain a rectangular target.
        if (style != 'simple') {
          expect(LayoutSpatialIndex(d).hitTest(229, 171), isNull);
        }
        final scene = compileScene(d)['items'] as List;
        expect(scene.where((i) => i.containsKey('hitPath')).length, 1);
        expect(compileSceneNodes(d, {n.id})['items'], scene);
        expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
        for (final contour in nodeOutlineContours(
          n.copyWith(properties: effectiveNodeProperties(d, n)),
        )) {
          for (final p in contour) {
            expect(p[0].abs(), lessThanOrEqualTo(30.001));
            expect(p[1].abs(), lessThanOrEqualTo(30.001));
          }
        }
      }
      expect(paths['simple'], isNot(paths['wood']));
      expect(paths['simple'], isNot(paths['lounge']));
      expect(paths['wood'], isNot(paths['lounge']));
    },
  );
  test('wooden backrests face away from rectangular and elliptical tables', () {
    for (final shape in ['rect', 'ellipse']) {
      final d = family(tableLayout(shape: shape, count: 8), 'wood');
      final table = d.nodes.first;
      for (final seat in d.nodes.where((n) => n.kind == 'seat')) {
        final body = item(d, seat.id), path = body['path'] as List;
        // The first closed contour is the broad wooden backrest.
        final back = <List<double>>[];
        for (final c in path) {
          if (c.first == 'Z') break;
          back.add([(c[1] as num).toDouble(), (c[2] as num).toDouble()]);
        }
        final x = back.map((p) => p[0]).reduce((a, b) => a + b) / back.length,
            y = back.map((p) => p[1]).reduce((a, b) => a + b) / back.length;
        final m = (body['matrix'] as List).cast<double>(),
            world = transformPoint(m, x, y);
        final seatWorld = transformPoint(m, 0, 0);
        expect(
          (world[0] - seatWorld[0]) * (seatWorld[0] - table.x) +
              (world[1] - seatWorld[1]) * (seatWorld[1] - table.y),
          greaterThan(0),
          reason: '$shape ${seat.rotation}',
        );
      }
    }
  });
  test(
    'moving a free chair preserves its stored facing and detaching preserves the world pose',
    () {
      for (final tableRotation in [0.0, 63.0]) {
        final source = family(
          tableLayout(shape: 'circle', count: 4, width: 180, height: 180),
          'lounge',
        );
        final table = source.nodes.first.copyWith(rotation: tableRotation);
        final original = source.nodes.firstWhere((n) => n.kind == 'seat');
        final seat = original.copyWith(
          x: -240,
          y: -60,
          rotation: 270,
          properties: original.properties,
          style: {'seatStyle': 'roundUpholstered'},
        );
        final d = source.copyWith(
          nodes: [
            for (final n in source.nodes)
              n.id == seat.id
                  ? seat
                  : n.id == table.id
                  ? table
                  : n,
          ],
        );
        for (final doc in [
          d,
          transformNodes(d, {seat.id}, dx: 30, dy: 20),
        ]) {
          final current = doc.nodes.firstWhere((n) => n.id == seat.id);
          final m = worldMatrix(doc, current);
          expect(current.rotation, 270);
          expect(item(doc, seat.id)['matrix'], m.map(quantize).toList());
          final detached = detachSeat(doc, seat.id);
          final free = detached.nodes.firstWhere((n) => n.id == seat.id);
          final freeMatrix = worldMatrix(detached, free);
          for (var i = 0; i < 6; i++) {
            expect(freeMatrix[i], closeTo(m[i], .001));
          }
        }
      }
    },
  );
  test(
    'explicit rotation overrides automatic facing and survives later movement',
    () {
      final d = family(
        tableLayout(shape: 'circle', count: 4, width: 180, height: 180),
        'lounge',
      );
      final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      final before = worldMatrix(d, seat);
      final rotated = transformNodes(d, {seat.id}, rotation: 37);
      final node = rotated.nodes.firstWhere((n) => n.id == seat.id);
      expect(seatAttachment(rotated, node.id)!['rotationMode'], 'manual');
      final expected = seat.rotation + 37;
      expect(node.rotation, closeTo(expected, .001));
      final moved = transformNodes(rotated, {seat.id}, dx: -60, dy: 45);
      final current = moved.nodes.firstWhere((n) => n.id == seat.id);
      expect(current.rotation, node.rotation);
      final matrix = worldMatrix(moved, current);
      expect(
        matrix.take(4).toList(),
        worldMatrix(rotated, node).take(4).toList(),
      );
      expect(matrix.take(4).toList(), isNot(before.take(4).toList()));
      expect(
        VenueLayoutDocument.fromJson(moved.toJson()).toJson(),
        moved.toJson(),
      );
      expect(validateDocument(moved), isEmpty);
    },
  );
  test(
    'manual chair orientation is preserved and matches the same hit contours',
    () {
      final d = tableLayout(shape: 'ellipse', count: 8), table = d.nodes.first;
      final seat = d.nodes
          .firstWhere((n) => n.kind == 'seat')
          .copyWith(rotation: 37, properties: {}, style: {'seatStyle': 'wood'});
      final resolved = seat.copyWith(
        properties: effectiveNodeProperties(d, seat),
      );
      final explicit = nodePath(resolved, parent: table),
          standalone = nodePath(resolved);
      expect(explicit, standalone);
      final updated = d.copyWith(
        nodes: [for (final n in d.nodes) n.id == seat.id ? seat : n],
      );
      expect(item(updated, seat.id)['path'], explicit);
    },
  );
  test(
    'round tables retain explicit shape while families change construction',
    () {
      for (final shape in ['circle', 'ellipse', 'rect']) {
        final d = tableLayout(shape: shape, count: 2), table = d.nodes.first;
        final basic = item(d, table.id)['path'];
        for (final style in ['wood', 'lounge']) {
          final themed = family(d, style);
          if (shape != 'rect') expect(item(themed, table.id)['path'], basic);
          expect(themed.nodes.first.surface, table.surface);
          final rim = item(themed, '${table.id}:table-style');
          expect((rim['path'] as List).length, greaterThan(4));
          expect(
            themed.nodes.first.surface!['type'],
            shape == 'rect' ? 'rect' : 'circle',
          );
          expect(themed.nodes.first.width, table.width);
        }
      }
    },
  );
  test(
    'couch construction differs without changing cushions or atomic membership',
    () {
      final d = couchLayout(), root = d.nodes.first;
      final outlines = <String, dynamic>{};
      for (final style in layoutObjectStyles) {
        final themed = family(d, style),
            arm = item(themed, '${root.id}:left-arm');
        outlines[style] = arm['path'];
        expect(themed.nodes, d.nodes);
        if (style == 'lounge') {
          final cushion = d.nodes.firstWhere((n) => n.kind == 'seat');
          expect(
            item(themed, cushion.id)['path'],
            isNot(item(d, cushion.id)['path']),
          );
        }
        expect(themed.selectionUnits, d.selectionUnits);
        expect(themed.attachments, d.attachments);
        expect(item(themed, root.id)['hitPath'], item(themed, root.id)['path']);
        expect(
          (compileScene(themed)['items'] as List).where(
            (i) => (i['id'] as String).endsWith(':seat-style'),
          ),
          isEmpty,
        );
        if (style == 'wood') expect(arm['fill'], '#B88755FF');
      }
      expect(outlines['simple'], isNot(outlines['wood']));
      expect(outlines['wood'], isNot(outlines['lounge']));
    },
  );
  test(
    'families keep host status foreground priority and reject invalid enum',
    () {
      final d = family(tableLayout(shape: 'rect', count: 2), 'wood');
      final seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      for (final state in [
        {'selected': true},
        {'status': 'occupied'},
        {'pending': true},
      ]) {
        final body = item(d, seat.id, presentation: {seat.id: state}),
            frame = item(
              d,
              '${seat.id}:seat-style',
              presentation: {seat.id: state},
            );
        expect(frame['fill'], body['fill']);
        expect(frame['stroke'], '#FFFFFF80');
      }
      expect(
        validateDocument(withKindStyle(d, 'seat', {'material': 'photo'})),
        isNotEmpty,
      );
      final malformed = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            n.id == seat.id
                ? n.copyWith(
                    properties: {...n.properties},
                    style: {'material': 3},
                  )
                : n,
        ],
      );
      expect(
        validateDocument(malformed).any((i) => i.reason == 'invalid_value'),
        isTrue,
      );
    },
  );
}
