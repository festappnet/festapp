import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test('immutable sparse quantized roundtrip', () {
    final props = {
      'shape': 'rect',
      'points': [
        [1, 2],
        [3, 4],
      ],
    };
    final n = LayoutNode(
      id: newLayoutId(),
      kind: 'shape',
      x: 3.123456,
      properties: props,
    );
    props['shape'] = 'ellipse';
    final d = VenueLayoutDocument(nodes: [n]);
    expect(n.properties['shape'], 'rect');
    expect(() => n.properties['points'][0][0] = 9, throwsUnsupportedError);
    final round = VenueLayoutDocument.fromJson(d.toJson());
    expect(round.nodes.single.x, quantize(n.x));
    expect(validateDocument(round), isEmpty);
  });
  test('unknown schema preserved', () {
    expect(
      () => VenueLayoutDocument.fromJson({'schemaVersion': 9, 'nodes': []}),
      throwsA(isA<UnsupportedLayoutSchema>()),
    );
  });
  test('cycles and duplicate unit membership', () {
    final a = newLayoutId(), b = newLayoutId();
    final d = VenueLayoutDocument(
      nodes: [
        LayoutNode(id: a, kind: 'seat', parentId: b),
        LayoutNode(id: b, kind: 'group', parentId: a),
      ],
      selectionUnits: [
        {
          'id': newLayoutId(),
          'kind': 'atomic',
          'nodeIds': [a],
        },
        {
          'id': newLayoutId(),
          'kind': 'atomic',
          'nodeIds': [a],
        },
      ],
    );
    expect(
      validateDocument(d).map((i) => i.reason),
      containsAll(['parent_cycle', 'duplicate_membership']),
    );
  });
  test('self intersection and colors', () {
    final d = VenueLayoutDocument(
      nodes: [
        LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          properties: {
            'shape': 'polygon',
            'points': [
              [-20, -20],
              [20, 20],
              [-20, 20],
              [20, -20],
            ],
          },
          style: {'fill': 'red'},
        ),
      ],
    );
    expect(
      validateDocument(d).map((i) => i.reason),
      containsAll(['self_intersection', 'invalid_value']),
    );
  });
  test('nested center transform and hit inverse', () {
    final parent = LayoutNode(
          id: newLayoutId(),
          kind: 'group',
          x: 300,
          y: 200,
          rotation: 37,
        ),
        seat = LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          parentId: parent.id,
          x: 80,
          y: 0,
        ),
        d = VenueLayoutDocument(nodes: [parent, seat]),
        m = worldMatrix(d, seat);
    expect(m[4], closeTo(300 + 80 * cos(37 * pi / 180), .001));
    expect(hitTest(d, m[4], m[5]), seat.id);
    expect(transformPoint(inverseMatrix(m), m[4], m[5])[0], closeTo(0, .001));
  });
  test('table reflow stable ids and detach preserves world', () {
    var d = tableLayout(shape: 'ellipse', count: 6, width: 200, height: 140);
    final table = d.nodes.first,
        ids = d.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet();
    d = reflowTable(d, table.id, 7);
    expect(d.nodes.map((n) => n.id).toSet().containsAll(ids), isTrue);
    d = d.copyWith(
      nodes: d.nodes
          .map((n) => n.id == table.id ? n.copyWith(rotation: 37) : n)
          .toList(),
    );
    final seat = d.nodes.firstWhere((n) => n.kind == 'seat'),
        before = worldMatrix(d, seat);
    d = detachSeat(d, seat.id);
    expect(
      worldMatrix(d, d.nodes.firstWhere((n) => n.id == seat.id))[4],
      closeTo(before[4], .001),
    );
    expect(validateDocument(d), isEmpty);
  });
  test('table manual override and capacity', () {
    var d = tableLayout(shape: 'roundedRect', count: 6);
    final seat = d.nodes.last;
    d = d.copyWith(
      nodes: d.nodes
          .map(
            (n) => n.id == seat.id
                ? n.copyWith(x: 999, properties: n.properties)
                : n,
          )
          .toList(),
    );
    d = d.copyWith(
      attachments: [
        for (final a in d.attachments)
          a['seatId'] == seat.id
              ? {
                  ...a,
                  'placement': {'mode': 'free'},
                }
              : a,
      ],
    );
    expect(
      reflowTable(
        d,
        d.nodes.first.id,
        6,
      ).nodes.firstWhere((n) => n.id == seat.id).x,
      999,
    );
    expect(() => reflowTable(d, d.nodes.first.id, 100), throwsArgumentError);
  });
  test('clone remaps selection units and attachments', () {
    final d = tableLayout(shape: 'ellipse', count: 4),
        unit = d.copyWith(
          selectionUnits: [
            {
              'id': newLayoutId(),
              'kind': 'atomic',
              'nodeIds': d.nodes
                  .where((n) => n.kind == 'seat')
                  .take(2)
                  .map((n) => n.id)
                  .toList(),
            },
          ],
        ),
        clone = cloneLayout(unit, dx: 100);
    expect(
      clone.nodes
          .map((n) => n.id)
          .toSet()
          .intersection(d.nodes.map((n) => n.id).toSet()),
      isEmpty,
    );
    expect(validateDocument(clone), isEmpty);
    expect(
      clone.nodes.firstWhere((n) => n.kind == 'table').x,
      d.nodes.first.x + 100,
    );
  });

  test('registration fit and clipping rejection', () {
    final m = registerTwoPoints([0, 0], [100, 0], [50, 70], [50, 270]);
    expect(transformPoint(m, 100, 0), [50, 270]);
    expect(
      () => registerTwoPoints([0, 0], [0, 0], [1, 1], [2, 2]),
      throwsArgumentError,
    );
    final d = tableLayout(shape: 'ellipse', count: 4, x: -100, y: -200);
    expect(fitCanvas(d).nodes, d.nodes);
    expect(fitCanvas(d).canvas['x'], lessThan(-100));
    expect(() => resizeCanvas(d, 64, 64), throwsStateError);
  });
  test(
    'canvas expansion preserves imports with existing boundary overflow',
    () {
      final node = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 0,
        y: 200,
        width: 2,
        height: 400,
      );
      final d = VenueLayoutDocument.empty().copyWith(
        canvas: {
          'x': 0,
          'y': 0,
          'width': 400,
          'height': 400,
          'fill': '#FFFFFFFF',
        },
        nodes: [node],
      );
      final expanded = resizeCanvas(d, 600, 400);
      expect(expanded.canvas['width'], 600);
      expect(expanded.nodes, d.nodes);
      expect(resizeCanvas(d, 600, 600, center: true).canvas['x'], -100);
      expect(() => resizeCanvas(d, 600, 300), throwsStateError);
    },
  );
  test('locks atomic group and ungroup retain transform', () {
    final d = tableLayout(shape: 'ellipse', count: 4),
        locked = d.copyWith(
          nodes: d.nodes
              .map((n) => n.kind == 'seat' ? n.copyWith(locked: true) : n)
              .toList(),
        );
    expect(
      () => transformNodes(locked, {d.nodes.first.id}, rotation: 30),
      throwsStateError,
    );
    final a = LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100),
        b = LayoutNode(id: newLayoutId(), kind: 'seat', x: 200, y: 100),
        plain = VenueLayoutDocument(nodes: [a, b]),
        grouped = groupNodes(plain, {a.id, b.id});
    expect(worldMatrix(grouped, a)[4], 100);
    expect(
      worldMatrix(ungroupNodes(grouped, {grouped.nodes.last.id}), a)[4],
      100,
    );
  });
  test('fit respects obstacle and never shrinks seats', () {
    final obstacle = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 76,
          y: 76,
          width: 70,
          height: 70,
          properties: {'obstacle': true},
        ),
        result = fitSeats(
          VenueLayoutDocument(nodes: [obstacle]),
          area: {'x': 0, 'y': 0, 'width': 200, 'height': 200},
          count: 9,
        );
    expect(validateDocument(result.document), isEmpty);
    expect(layoutCollisions(result.document), isEmpty);
    expect(result.placed, lessThan(9));
    expect(
      result.document.nodes
          .where((n) => n.kind == 'seat')
          .every((n) => n.width == 40),
      isTrue,
    );
  });
  test('generator slot reconciliation preserves manual ids', () {
    final d = rowLayout(rows: 2, seatsPerRow: 3),
        root = d.nodes.first,
        seat = d.nodes[1],
        manual = d.copyWith(
          nodes: d.nodes
              .map(
                (n) => n.id == seat.id
                    ? n.copyWith(x: 500, properties: n.properties)
                    : n,
              )
              .toList(),
        ),
        next = reconcileAssembly(
          manual.copyWith(
            attachments: [
              for (final a in manual.attachments)
                a['seatId'] == seat.id
                    ? {
                        ...a,
                        'placement': {'mode': 'free'},
                      }
                    : a,
            ],
          ),
          root.id,
          rowLayout(rows: 3, seatsPerRow: 3),
        );
    expect(next.nodes.firstWhere((n) => n.id == seat.id).x, 500);
    expect(next.nodes.length, 10);
    expect(busLayout().nodes.where((n) => n.kind == 'seat').length, 45);
    expect(compartmentLayout().nodes.where((n) => n.kind == 'seat').length, 24);
  });
  test('motion endpoints and independent presets', () {
    final d = tableLayout(shape: 'ellipse', count: 4),
        end = transformNodes(d, {d.nodes.first.id}, dx: 50, rotation: 90);
    expect(interpolateLayout(d, end, 0).nodes.first.x, d.nodes.first.x);
    expect(interpolateLayout(d, end, 1).nodes.first.x, end.nodes.first.x);
    final saved = savePreset(d, {d.nodes.first.id}, 'Table'),
        next = instantiatePreset(saved, saved.presets.single['id']);
    expect(next.nodes.length, d.nodes.length * 2);
    expect(validateDocument(next), isEmpty);
  });
  test('5000 sparse seats validate and index', () {
    final d = rowLayout(rows: 100, seatsPerRow: 50),
        watch = Stopwatch()..start();
    expect(validateDocument(d), isEmpty);
    expect(LayoutSpatialIndex(d).hitTest(100, 100), isNotNull);
    expect(watch.elapsedMilliseconds, lessThan(3000));
  });

  test(
    'concave collision excludes notch and fitting checks full polygon hull',
    () {
      final room = <List<double>>[
        [0, 0],
        [220, 0],
        [220, 70],
        [70, 70],
        [70, 220],
        [0, 220],
      ];
      final notch = <List<double>>[
        [100, 100],
        [140, 100],
        [140, 140],
        [100, 140],
      ];
      expect(polygonsOverlap(room, notch), isFalse);
      expect(
        polygonsOverlap(room, [
          [20, 20],
          [50, 20],
          [50, 50],
          [20, 50],
        ]),
        isTrue,
      );
      final result = fitSeats(
        VenueLayoutDocument.empty(),
        area: {'x': 0, 'y': 0, 'width': 220, 'height': 220},
        boundary: room,
        count: 20,
      );
      expect(
        result.document.nodes.every(
          (n) => polygonContainsHull(room, worldHull(n, localMatrix(n))),
        ),
        isTrue,
      );
    },
  );
  test('bounded async fit cancellation reports incomplete result', () async {
    var cancel = false;
    final future = fitSeatsAsync(
      VenueLayoutDocument.empty(),
      area: {'x': 0, 'y': 0, 'width': 1000000, 'height': 1000000},
      count: 20000,
      cancelled: () => cancel,
    );
    Future<void>.delayed(Duration.zero, () => cancel = true);
    final result = await future;
    expect(result.complete, isFalse);
    expect(result.unplaced, greaterThan(0));
  });
  test('cached node scene patches match full scene and contain bounds', () {
    final d = tableLayout(shape: 'ellipse', count: 4),
        id = d.nodes.last.id,
        presentation = <String, dynamic>{
          id: {'selected': true},
        };
    final full = compileScene(d, presentation: presentation),
        patch = compileSceneNodes(d, {id}, presentation: presentation);
    expect(
      patch['items'],
      (full['items'] as List)
          .where((item) => item['id'] == id || item['nodeId'] == id)
          .toList(),
    );
    expect(
      (patch['items'] as List).every((item) => item['bounds'] is Map),
      isTrue,
    );
    expect(
      compileScene(
        VenueLayoutDocument(
          nodes: [
            LayoutNode(id: newLayoutId(), kind: 'group', parentId: 'missing'),
          ],
        ),
      )['issues'],
      isNotEmpty,
    );
  });

  test(
    'sampled variants rank capacity then deviation and share bounded budget',
    () async {
      final result = await fitSeatVariantsAsync(
        VenueLayoutDocument.empty(),
        area: {'x': 0, 'y': 0, 'width': 230, 'height': 230},
        count: 16,
        spacing: 64,
        rowSpacing: 64,
        minSpacing: 48,
        maxSpacing: 72,
        spacingStep: 8,
        minRowSpacing: 48,
        maxRowSpacing: 72,
        rowSpacingStep: 8,
      );
      expect(result.variants, isNotEmpty);
      expect(result.tried, lessThanOrEqualTo(100000));
      final counts = result.variants.map((v) => v.result.placed).toList();
      expect(
        counts,
        orderedEquals(counts.toList()..sort((a, b) => b.compareTo(a))),
      );
      expect(
        result.variants.first.result.document.nodes.every(
          (n) => n.width == 40 && n.height == 40,
        ),
        isTrue,
      );
    },
  );
  test(
    'rotated row snap uses parent axes and spatial neighbour uses world centres',
    () {
      var d = rowLayout(rows: 1, seatsPerRow: 3, x: 200, y: 200);
      final root = d.nodes.first;
      d = d.copyWith(
        nodes: d.nodes
            .map((n) => n.id == root.id ? n.copyWith(rotation: 37) : n)
            .toList(),
      );
      final first = d.nodes[1],
          second = d.nodes[2],
          angle = 37 * pi / 180,
          snap = snapTranslation(
            d,
            {first.id},
            -sin(angle) * 3,
            cos(angle) * 3,
          );
      expect(snap.dx, closeTo(0, .002));
      expect(snap.dy, closeTo(0, .002));
      expect(nearestNode(d, first.id, 'right'), second.id);
    },
  );
  test('scene interpolation endpoints shared easing paths and bounds', () {
    final d = VenueLayoutDocument(
          nodes: [LayoutNode(id: newLayoutId(), kind: 'seat', x: 100, y: 100)],
        ),
        end = transformNodes(d, {d.nodes.first.id}, dx: 80, rotation: 90),
        a = compileScene(d),
        b = compileScene(end);
    expect(interpolateScene(a, b, 0), same(a));
    expect(interpolateScene(a, b, 1), same(b));
    final mid = interpolateScene(a, b, .5), item = (mid['items'] as List).first;
    expect(item['matrix'][4], 170);
    expect(item['bounds'], isA<Map>());
    expect(layoutEaseOut(.5), .875);
  });
  test(
    'furniture physical hull excludes internal seats but collides externally',
    () {
      final couch = LayoutNode(
            id: newLayoutId(),
            kind: 'furniture',
            x: 100,
            y: 100,
            width: 120,
            height: 60,
          ),
          seat = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            parentId: couch.id,
          ),
          external = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: 150,
            y: 100,
          );
      expect(
        layoutCollisions(VenueLayoutDocument(nodes: [couch, seat])),
        isEmpty,
      );
      expect(
        layoutCollisions(
          VenueLayoutDocument(nodes: [couch, seat, external]),
        ).any((p) => p.contains(couch.id) && p.contains(external.id)),
        isTrue,
      );
    },
  );
  test(
    'crop clips native pixels in place under unchanged uniform world registration',
    () {
      final background = <String, dynamic>{
        'assetRef': 'crop-test',
        'hash':
            '0000000000000000000000000000000000000000000000000000000000000000',
        'width': 100,
        'height': 80,
        'x': 300,
        'y': 200,
        'scale': 2,
        'rotation': 0,
        'crop': {'x': .1, 'y': .2, 'width': .6, 'height': .4},
      };
      final d = VenueLayoutDocument(background: background),
          item =
              (compileScene(d)['items'] as List).single as Map<String, dynamic>;
      expect(item['sourceRect'], {
        'x': 10.0,
        'y': 16.0,
        'width': 60.0,
        'height': 32.0,
      });
      expect(item['destinationRect'], {
        'x': -40.0,
        'y': -24.0,
        'width': 60.0,
        'height': 32.0,
      });
      expect(item['matrix'], [2.0, 0.0, 0.0, 2.0, 300.0, 200.0]);
      expect(item['bounds'], {
        'x': 220.0,
        'y': 152.0,
        'width': 120.0,
        'height': 64.0,
      });
      expect(item['clip'], d.canvas);
      final full =
          (compileScene(
                    d.copyWith(
                      background: {
                        ...background,
                        'crop': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
                      },
                    ),
                  )['items']
                  as List)
              .single;
      expect(item['matrix'], full['matrix']);
    },
  );
  test(
    'alignment and equal gaps use world subtree bounds and reject locks atomically',
    () {
      final a = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: 100,
            y: 100,
            width: 40,
            height: 40,
          ),
          b = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: 190,
            y: 180,
            width: 60,
            height: 40,
          ),
          c = LayoutNode(
            id: newLayoutId(),
            kind: 'seat',
            x: 300,
            y: 220,
            width: 40,
            height: 40,
          ),
          d = VenueLayoutDocument(nodes: [a, b, c]),
          ids = {a.id, b.id, c.id};
      final aligned = alignNodes(d, ids, 'top');
      expect(
        aligned.nodes.map((n) => nodeBounds(aligned, n)['y']),
        everyElement(80.0),
      );
      final distributed = distributeNodes(d, ids),
          sorted = distributed.nodes.toList()
            ..sort((a, b) => a.x.compareTo(b.x));
      final gap1 =
              sorted[1].x -
              sorted[1].width / 2 -
              sorted[0].x -
              sorted[0].width / 2,
          gap2 =
              sorted[2].x -
              sorted[2].width / 2 -
              sorted[1].x -
              sorted[1].width / 2;
      expect(gap1, closeTo(gap2, .002));
      final locked = d.copyWith(nodes: [a, b.copyWith(locked: true), c]);
      expect(() => alignNodes(locked, ids, 'right'), throwsStateError);
      final nested = groupNodes(d, {a.id, b.id});
      expect(
        alignNodes(nested, {
          nested.nodes.last.id,
          a.id,
          c.id,
        }, 'left').nodes.where((n) => n.id == a.id).single.parentId,
        nested.nodes.last.id,
      );
    },
  );
  test(
    'layer order follows sibling z and dashed geometry is materialized once',
    () {
      final a = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            x: 100,
            y: 100,
            properties: {'shape': 'line'},
            style: {
              'strokePattern': {
                'type': 'custom',
                'lengths': [12, 8],
              },
            },
          ),
          b = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            x: 200,
            y: 100,
            z: 1,
          ),
          seat = LayoutNode(id: newLayoutId(), kind: 'seat', z: 2),
          d = VenueLayoutDocument(nodes: [a, b, seat]),
          reordered = reorderNodes(d, {a.id}, 1);
      expect(
        orderedNodes(reordered).indexWhere((n) => n.id == a.id),
        greaterThan(orderedNodes(reordered).indexWhere((n) => n.id == b.id)),
      );
      expect(orderedNodes(reordered).last.id, seat.id);
      final scene = compileSceneNodes(d, {a.id}),
          items = (scene['items'] as List).cast<Map<String, dynamic>>(),
          stroke = items.singleWhere((i) => i['kind'] == 'stroke');
      expect(stroke['nodeId'], a.id);
      expect(stroke['path'], [
        ['M', -20.0, 0.0],
        ['L', -8.0, 0.0],
        ['M', 0.0, 0.0],
        ['L', 12.0, 0.0],
      ]);
      expect(items.every((i) => !i.containsKey('dash')), isTrue);
      final ellipse = dashedPath(
        nodePath(
          LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            properties: {'shape': 'ellipse'},
          ),
        ),
        [4, 3],
      );
      expect(
        ellipse,
        everyElement(predicate((dynamic c) => c[0] == 'M' || c[0] == 'L')),
      );
    },
  );
}
