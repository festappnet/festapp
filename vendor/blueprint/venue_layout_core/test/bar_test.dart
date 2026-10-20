import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

List<LayoutNode> stools(VenueLayoutDocument d) =>
    d.nodes.where((n) => n.kind == 'seat').toList();
void guestOnly(VenueLayoutDocument d) {
  final bar = d.nodes.firstWhere(isBarNode);
  for (final stool in stools(d)) {
    expect(isStoolNode(stool, parent: bar), isTrue);
    expect(switch (bar.properties['guestSide']) {
      'top' => stool.y < -bar.height / 2,
      'bottom' => stool.y > bar.height / 2,
      'left' => stool.x < -bar.width / 2,
      'right' => stool.x > bar.width / 2,
      _ => false,
    }, isTrue);
  }
  expect(validateDocument(d), isEmpty);
}

void main() {
  for (final side in barGuestSides) {
    test('bar materializes stable stools on $side guest side only', () {
      final horizontal = side == 'top' || side == 'bottom';
      final d = barLayout(
        count: 4,
        guestSide: side,
        width: horizontal ? 280 : 72,
        height: horizontal ? 72 : 280,
      );
      expect(tableCapacity(d.nodes.first), 4);
      expect(barSeatCount(d, d.nodes.first.id), 4);
      expect(d.selectionUnits, isEmpty);
      guestOnly(d);
      expect(
        stools(d).every((n) => n.properties['furniture'] == 'stool'),
        isTrue,
      );
      expect(
        d.attachments.every((a) => a['placement']?['mode'] == 'automatic'),
        isTrue,
      );
      expect(layoutCollisions(d), isEmpty);
      expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
      final more = resizeNode(
        d,
        d.nodes.first.id,
        horizontal ? 384 : 72,
        horizontal ? 72 : 384,
      );
      final expanded = reflowBar(more, d.nodes.first.id, 6);
      expect(
        stools(expanded).take(4).map((n) => n.id),
        stools(d).map((n) => n.id),
      );
      guestOnly(expanded);
      expect(expanded.canvas, d.canvas);
    });
  }
  test(
    'shrink removes free stools but preserves protected IDs and rejects insufficient capacity',
    () {
      final d = barLayout(count: 4),
          bar = d.nodes.first,
          protected = stools(d).last.id;
      final resized = resizeNode(
        d,
        bar.id,
        128,
        72,
        protectedSeatIds: {protected},
      );
      expect(stools(resized).length, 2);
      expect(stools(resized).any((n) => n.id == protected), isTrue);
      expect(
        stools(resized).every((n) => stools(d).any((old) => old.id == n.id)),
        isTrue,
      );
      expect(resized.attachments.length, 2);
      guestOnly(resized);
      final before = d.toJson();
      expect(
        () => resizeNode(
          d,
          bar.id,
          128,
          72,
          protectedSeatIds: stools(d).take(3).map((n) => n.id).toSet(),
        ),
        throwsA(isA<TableResizeRejected>()),
      );
      expect(d.toJson(), before);
    },
  );
  test(
    'guest-side changes retain IDs and reject a too-short or locked configuration',
    () {
      final d = barLayout(count: 4), bar = d.nodes.first;
      final changed = setBarGuestSide(
        d,
        bar.id,
        'top',
        protectedSeatIds: {stools(d).first.id},
      );
      expect(stools(changed).map((n) => n.id), stools(d).map((n) => n.id));
      guestOnly(changed);
      expect(
        changed.attachments.every(
          (a) => a['placement']?['mode'] == 'automatic',
        ),
        isTrue,
      );
      expect(() => setBarGuestSide(d, bar.id, 'left'), throwsStateError);
      final locked = d.copyWith(
        nodes: [
          for (final n in d.nodes)
            n.id == stools(d).first.id ? n.copyWith(locked: true) : n,
        ],
      );
      expect(() => setBarGuestSide(locked, bar.id, 'top'), throwsStateError);
    },
  );
  for (final rotation in [0.0, 37.0]) {
    test(
      'bar wall drag $rotation clamps whole assembly without service-side jumps',
      () {
        var d = barLayout(count: 4, x: 600, y: 400).copyWith(
          canvas: {
            'x': 0,
            'y': 0,
            'width': 1200,
            'height': 800,
            'fill': '#FFFFFFFF',
          },
        );
        final bar = d.nodes.first;
        d = d.copyWith(
          nodes: [
            for (final n in d.nodes)
              n.id == bar.id ? n.copyWith(rotation: rotation) : n,
          ],
        );
        for (final delta in [
          [0.0, 10000.0],
          [0.0, -10000.0],
          [-10000.0, 0.0],
          [10000.0, 0.0],
        ]) {
          final moved = moveLayoutWithinCanvas(
            d,
            {bar.id},
            dx: delta[0],
            dy: delta[1],
          );
          guestOnly(moved);
          expect(moved.canvas, d.canvas);
          expect(stools(moved).map((n) => n.id), stools(d).map((n) => n.id));
          for (final n in moved.nodes) {
            for (final p in worldHull(n, worldMatrix(moved, n))) {
              expect(p[0], inInclusiveRange(-.2, 1200.2));
              expect(p[1], inInclusiveRange(-.2, 800.2));
            }
          }
        }
      },
    );
  }
  test(
    'bar-derived and detached explicit stools share real silhouette hit geometry across families',
    () {
      final bar = barLayout(count: 4), root = bar.nodes.first;
      final ordinary = LayoutNode(
        id: newLayoutId(),
        kind: 'seat',
        x: 100,
        y: 100,
      );
      final attached = attachSeat(
        reflowBar(
          bar,
          root.id,
          3,
        ).copyWith(nodes: [...reflowBar(bar, root.id, 3).nodes, ordinary]),
        ordinary.id,
        root.id,
      );
      expect(
        isStoolNode(
          attached.nodes.firstWhere((n) => n.id == ordinary.id),
          parent: root,
        ),
        isTrue,
      );
      for (final family in layoutObjectStyles) {
        final d = bar.copyWith(
          styles: {
            'kinds': {
              for (final kind in layoutAppearanceKinds)
                kind: {
                  if (kind != 'text') 'material': family,
                  if (kind == 'seat')
                    'seatStyle': family == 'wood'
                        ? 'wood'
                        : family == 'lounge'
                        ? 'upholstered'
                        : 'plain',
                },
            },
          },
        );
        final full = compileScene(d)['items'] as List;
        expect(full.any((i) => i['id'] == '${root.id}:bar-front'), isTrue);
        for (final stool in stools(d)) {
          final body = full.singleWhere((i) => i['id'] == stool.id);
          expect(body['path'], body['hitPath']);
          expect(
            LayoutSpatialIndex(d).hitTest(root.x + stool.x, root.y + stool.y),
            stool.id,
          );
          expect(
            compileSceneNodes(d, {stool.id})['items'],
            full
                .where((i) => i['id'] == stool.id || i['nodeId'] == stool.id)
                .toList(),
          );
        }
      }
      final detached = detachSeat(bar, stools(bar).first.id),
          stool = detached.nodes.firstWhere(
            (n) => n.id == stools(bar).first.id,
          );
      expect(stool.parentId, isNull);
      expect(isStoolNode(stool), isTrue);
    },
  );
  test(
    'bar invalid side kind shape and service-side stool payloads reject',
    () {
      final d = barLayout(count: 4), bar = d.nodes.first;
      for (final properties in [
        {...bar.properties, 'guestSide': 'any'},
        {...bar.properties}..remove('guestSide'),
        {...bar.properties, 'shape': 'ellipse'},
      ])
        expect(
          validateDocument(
            d.copyWith(
              nodes: [
                bar.copyWith(properties: properties),
                ...stools(d),
              ],
            ),
          ),
          isNotEmpty,
        );
      final badSeat = stools(d).first.copyWith(y: -100);
      expect(
        validateDocument(
          d.copyWith(
            nodes: [for (final n in d.nodes) n.id == badSeat.id ? badSeat : n],
          ),
        ).any((i) => i.reason == 'bar_stool_wrong_side'),
        isTrue,
      );
      expect(() => barLayout(guestSide: 'unknown'), throwsArgumentError);
      expect(() => barLayout(width: double.nan), throwsArgumentError);
    },
  );
  test(
    'curved table rims preserve circle/ellipse ratio and wood mark clears centered label',
    () {
      final resources = Map<String, dynamic>.from(
        jsonDecode(
          File('../../assets/layout_fonts/fixtures.json').readAsStringSync(),
        ),
      );
      for (final shape in ['circle', 'ellipse']) {
        final d = tableLayout(
          shape: shape,
          count: 2,
          width: 160,
          height: shape == 'circle' ? 160 : 100,
        );
        final root = d.nodes.first;
        for (final style in ['wood', 'lounge']) {
          for (final rotation in [0.0, 90.0]) {
            final themed = d.copyWith(
              nodes: [
                for (final n in d.nodes)
                  n.id == root.id
                      ? n.copyWith(label: 'Table 1', rotation: rotation)
                      : n,
              ],
              styles: {
                'kinds': {
                  'table': {'material': style},
                },
              },
            );
            final items =
                compileScene(themed, resources: resources)['items'] as List;
            final rim =
                    items.singleWhere(
                          (i) => i['id'] == '${root.id}:table-style',
                        )
                        as Map<String, dynamic>,
                path = rim['path'] as List;
            final outer = path.takeWhile((c) => c.first != 'Z').toList();
            final xs = [
                  for (final c in outer)
                    for (var i = 1; i < c.length; i += 2)
                      (c[i] as num).toDouble(),
                ],
                ys = [
                  for (final c in outer)
                    for (var i = 2; i < c.length; i += 2)
                      (c[i] as num).toDouble(),
                ];
            xs.sort();
            ys.sort();
            expect(
              (xs.last - xs.first) / (ys.last - ys.first),
              closeTo(root.width / root.height, .0001),
            );
            if (style == 'wood') {
              expect(path.any((c) => c.first == 'L'), isFalse);
              final mark = Map<String, dynamic>.from(rim)
                ..['path'] = path
                    .skipWhile((c) => c.first != 'Z')
                    .skip(1)
                    .toList();
              final label =
                  items.singleWhere((i) => i['id'] == '${root.id}:text')
                      as Map<String, dynamic>;
              final labelMatrix = (label['matrix'] as List).cast<double>();
              final relativeMark = {
                ...mark,
                'matrix': multiplyMatrix(
                  inverseMatrix(labelMatrix),
                  (mark['matrix'] as List).cast<double>(),
                ),
              };
              final localLabel = {
                ...label,
                'matrix': [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
              };
              final markBounds = sceneItemBounds(relativeMark),
                  labelBounds = sceneItemBounds(localLabel);
              expect(
                markBounds['y']! + markBounds['height']!,
                lessThan(labelBounds['y']! - 2),
              );
            }
          }
        }
      }
    },
  );
}
