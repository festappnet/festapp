import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

VenueLayoutDocument plan() => VenueLayoutDocument(
  schemaVersion: 2,
  seatingDefaults: {
    'width': 30,
    'height': 40,
    'gap': 10,
    'spacing': 12,
    'edgePadding': 12,
  },
  nodes: [
    LayoutNode(
      id: '30000000-0000-4000-8000-000000000001',
      kind: 'table',
      x: 600,
      y: 500,
      width: 300,
      height: 180,
      surface: {'type': 'rect'},
    ),
  ],
);
void main() {
  test(
    'assembly variants reject missing, foreign, impossible and wrong-root declarations',
    () {
      final d = rowLayout(rows: 2, seatsPerRow: 3), root = d.nodes.first;
      final missing = {...root.assembly!}..remove('spacing');
      for (final spec in [
        missing,
        {...root.assembly!, 'left': 2},
        {...root.assembly!, 'spacing': 0},
        {...root.assembly!, 'rows': 1000000},
      ]) {
        expect(
          validateDocument(
            d.copyWith(
              nodes: [
                for (final node in d.nodes)
                  node.id == root.id ? node.copyWith(assembly: spec) : node,
              ],
            ),
          ),
          isNotEmpty,
        );
      }
      expect(
        validateDocument(
          d.copyWith(
            nodes: [
              for (final node in d.nodes)
                node.id == root.id ? node.copyWith(kind: 'furniture') : node,
            ],
          ),
        ),
        isNotEmpty,
      );
    },
  );

  test(
    'surface kind changes keep complete seat inventory and declare only typed geometry',
    () {
      var d = tableLayout(
            shape: 'roundedRect',
            count: 4,
            width: 220,
            height: 160,
          ),
          table = d.nodes.firstWhere((node) => node.kind == 'table');
      final ids = d.nodes
          .where((node) => node.kind == 'seat')
          .map((node) => node.id)
          .toSet();
      for (final kind in ['circle', 'rect', 'grid']) {
        d = setTableSurfaceKind(d, table.id, kind, protectedSeatIds: ids);
        expect(validateDocument(d), isEmpty);
        table = d.nodes.firstWhere((node) => node.id == table.id);
        expect(table.surface!['type'], kind);
        expect(table.properties.containsKey('shape'), isFalse);
        expect(
          d.nodes
              .where((node) => node.kind == 'seat')
              .map((node) => node.id)
              .toSet(),
          ids,
        );
      }
      final locked = d.copyWith(
        nodes: [
          for (final node in d.nodes)
            node.id == table.id ? node.copyWith(locked: true) : node,
        ],
      );
      expect(
        () => setTableSurfaceKind(locked, table.id, 'rect'),
        throwsStateError,
      );
    },
  );

  test(
    'grid boundary pins rebase their cells during left extension and reject interior or empty faces',
    () {
      final table = LayoutNode(
        id: newLayoutId(),
        kind: 'table',
        x: 500,
        y: 400,
        width: 120,
        height: 80,
        seating: const TableSeating().record,
        surface: {
          'type': 'grid',
          'moduleSize': 40,
          'outer': [
            [0, 0],
            [3, 0],
            [3, 2],
            [0, 2],
          ],
          'holes': [],
        },
      );
      var d = reflowTable(
        VenueLayoutDocument(schemaVersion: 2, nodes: [table]),
        table.id,
        1,
      );
      final seat = d.nodes.firstWhere((node) => node.kind == 'seat');
      d = setTableSeatPlacement(d, seat.id, {
        'mode': 'sidePinned',
        'cell': [0, 0],
        'face': 'top',
      });
      final oldPose = worldMatrix(
        d,
        d.nodes.firstWhere((node) => node.id == seat.id),
      );
      final changed = extendGridTableSurface(
        d,
        table.id,
        3,
        -100,
        0,
        cellIndex: 0,
      );
      expect(validateDocument(changed), isEmpty);
      expect(changed.attachments.single['placement'], {
        'mode': 'sidePinned',
        'cell': [1, 0],
        'face': 'top',
      });
      expect(
        worldMatrix(
          changed,
          changed.nodes.firstWhere((node) => node.id == seat.id),
        ),
        oldPose,
      );
      for (final placement in [
        {
          'mode': 'sidePinned',
          'cell': [1, 0],
          'face': 'right',
        },
        {
          'mode': 'sidePinned',
          'cell': [3, 0],
          'face': 'top',
        },
        {'mode': 'sidePinned', 'side': 'top', 't': 0.5},
      ]) {
        expect(
          () => setTableSeatPlacement(d, seat.id, placement),
          throwsA(isA<InvalidLayoutDocument>()),
        );
      }
    },
  );

  test(
    'table and bar factories author canonical surfaces and physical profiles directly',
    () {
      for (final document in [
        tableLayout(
          shape: 'roundedRect',
          count: 4,
          seating: const TableSeating(width: 44, height: 36),
        ),
        tableLayout(shape: 'ellipse', width: 160, height: 160, count: 6),
        barLayout(count: 3),
      ]) {
        expect(document.schemaVersion, 2);
        expect(validateDocument(document), isEmpty);
        final root = document.nodes.firstWhere((node) => node.kind == 'table');
        expect(root.surface, isNotNull);
        expect(root.properties.containsKey('shape'), isFalse);
        expect(root.properties.containsKey('seatWidth'), isFalse);
        expect(
          document.attachments.length,
          document.nodes.where((node) => node.kind == 'seat').length,
        );
      }
    },
  );

  test(
    'canonical row creation and count commands retain authored seats and custom children atomically',
    () {
      final created = rowLayout(rows: 2, seatsPerRow: 3, x: 500, y: 400),
          root = created.nodes.firstWhere((node) => node.kind == 'group'),
          first = created.nodes.firstWhere((node) => node.kind == 'seat');
      expect(validateDocument(created), isEmpty);
      expect(
        created.nodes.every(
          (node) =>
              !node.properties.containsKey('assembly') &&
              !node.properties.containsKey('size'),
        ),
        isTrue,
      );
      final moved = transformNodes(created, {first.id}, dx: 4, rotation: 37),
          decoration = LayoutNode(
            id: newLayoutId(),
            kind: 'shape',
            parentId: root.id,
            x: 250,
            y: -50,
            width: 10,
            height: 10,
          );
      final before = moved.copyWith(nodes: [...moved.nodes, decoration]);
      final grown = reconcileAssembly(
        before,
        root.id,
        rowLayout(rows: 3, seatsPerRow: 3),
      );
      expect(validateDocument(grown), isEmpty);
      expect(grown.nodes.where((node) => node.kind == 'seat'), hasLength(9));
      expect(
        grown.nodes.firstWhere((node) => node.id == first.id).toJson(),
        before.nodes.firstWhere((node) => node.id == first.id).toJson(),
      );
      expect(
        grown.nodes.firstWhere((node) => node.id == decoration.id).toJson(),
        decoration.toJson(),
      );
      expect(grown.attachments, hasLength(9));
      expect(
        grown.nodes
            .map((node) => node.id)
            .toSet()
            .containsAll(before.nodes.map((node) => node.id)),
        isTrue,
      );
      final pair = created.nodes
          .where(
            (node) =>
                node.properties['slot'] == '0:0:1' ||
                node.properties['slot'] == '1:0:1',
          )
          .map((node) => node.id)
          .toList();
      final atomic = before.copyWith(
        selectionUnits: [
          {'id': newLayoutId(), 'kind': 'atomic', 'nodeIds': pair},
        ],
      );
      expect(
        () => reconcileAssembly(
          atomic,
          root.id,
          rowLayout(rows: 1, seatsPerRow: 3),
        ),
        throwsStateError,
      );
      expect(atomic.nodes.length, before.nodes.length);
    },
  );

  test(
    'typed rows keep signed curvature, free positions and independent rotations without runtime inference',
    () {
      final base = rowLayout(rows: 2, seatsPerRow: 3, x: 600, y: 400, arc: -2);
      final chair = base.nodes.firstWhere((node) => node.kind == 'seat');
      final document = base.copyWith(
            nodes: [
              for (final n in base.nodes)
                n.id == chair.id ? n.copyWith(x: n.x + 4, rotation: 37) : n,
            ],
            attachments: [
              for (final a in base.attachments)
                a['seatId'] == chair.id
                    ? {
                        ...a,
                        'placement': {'mode': 'free'},
                        'rotationMode': 'manual',
                      }
                    : a,
            ],
          ),
          root = document.nodes.firstWhere((node) => node.kind == 'group');
      expect(validateDocument(document), isEmpty);
      expect(root.assembly!['arc'], -2);
      expect(root.properties.containsKey('rows'), isFalse);
      expect(seatAttachment(document, chair.id)!['placement'], {
        'mode': 'free',
      });
      expect(seatAttachment(document, chair.id)!['rotationMode'], 'manual');
      final bounds = rowAssemblyBounds(document, root.id),
          resized = resizeRowAssembly(
            document,
            root.id,
            bounds['width']! * 1.25,
            bounds['height']! * 1.15,
          );
      expect(validateDocument(resized), isEmpty);
      final kept = resized.nodes.firstWhere((node) => node.id == chair.id),
          before = document.nodes.firstWhere((node) => node.id == chair.id);
      expect(kept.toJson(), before.toJson());
      expect(
        resized.nodes.map((node) => node.id).toSet(),
        document.nodes.map((node) => node.id).toSet(),
      );
      expect(
        rowLayoutParameters(resized, root.id)['spacing'],
        resized.nodes
            .firstWhere((node) => node.id == root.id)
            .assembly!['spacing'],
      );
      final invalid = document.copyWith(
        nodes: [
          for (final node in document.nodes)
            node.id == root.id
                ? node.copyWith(assembly: {...root.assembly!, 'rows': 1.5})
                : node,
        ],
      );
      expect(validateDocument(invalid), isNotEmpty);
    },
  );

  test(
    'canonical rendering uses the stored seat rotation independently of placement policy',
    () {
      final d = reflowTable(plan(), plan().nodes.single.id, 2),
          seat = d.nodes.firstWhere((node) => node.kind == 'seat');
      final changed = d.copyWith(
        nodes: [
          for (final node in d.nodes)
            node.id == seat.id ? node.copyWith(rotation: 37) : node,
        ],
      );
      final stored = changed.nodes.firstWhere((node) => node.id == seat.id),
          table = changed.nodes.firstWhere(
            (node) => node.id == stored.parentId,
          );
      final expected = multiplyMatrix(localMatrix(table), localMatrix(stored));
      expect(worldMatrix(changed, stored), expected.map(quantize).toList());
      final item = (compileScene(changed)['items'] as List).firstWhere(
        (item) => (item['nodeId'] ?? item['id']) == stored.id,
      );
      expect(item['matrix'], expected.map(quantize).toList());
    },
  );

  test(
    'side commands pin one seat, retain free exceptions and preserve manual rotation',
    () {
      final initial = reflowTable(plan(), plan().nodes.single.id, 4),
          seats = initial.nodes.where((node) => node.kind == 'seat').toList();
      final free = transformNodes(initial, {seats[1].id}, dx: 5, dy: 0),
          manual = transformNodes(free, {seats[0].id}, rotation: 17);
      final kept = manual.nodes.firstWhere((node) => node.id == seats[1].id),
          rotated = manual.nodes.firstWhere((node) => node.id == seats[0].id);
      final next = moveTableSeatToSide(manual, seats[0].id, 'left');
      expect(validateDocument(next), isEmpty);
      expect(
        next.nodes.map((node) => node.id).toSet(),
        initial.nodes.map((node) => node.id).toSet(),
      );
      expect(
        seatAttachment(next, seats[0].id)!['placement']['mode'],
        'sidePinned',
      );
      expect(
        tableSideForSeat(
          next,
          next.nodes.firstWhere((node) => node.id == seats[0].id),
        ),
        'left',
      );
      expect(
        next.nodes.firstWhere((node) => node.id == kept.id).toJson(),
        kept.toJson(),
      );
      expect(
        next.nodes.firstWhere((node) => node.id == rotated.id).rotation,
        rotated.rotation,
      );
      final automatic = setTableSeatPlacement(next, rotated.id, {
        'mode': 'automatic',
      });
      expect(seatAttachment(automatic, rotated.id)!['rotationMode'], 'manual');
    },
  );

  test(
    'painted canonical grids retain integer rings and stored module size on edit',
    () {
      final brush = GridSurfaceBrush(
        step: 37.5,
        originX: -37.5,
        originY: -37.5,
      );
      for (final cell in [(0, 0), (1, 0), (0, 1)]) {
        brush.stampCell(cell.$1, cell.$2);
      }
      final node = brush.node(id: newLayoutId());
      final d = VenueLayoutDocument(schemaVersion: 2, nodes: [node]);
      expect(validateDocument(d), isEmpty);
      expect(node.properties, isEmpty);
      expect(node.surface!['moduleSize'], 37.5);
      expect(
        (node.surface!['outer'] as List).every(
          (p) => (p as List).every((v) => v is int),
        ),
        isTrue,
      );
      final restored = GridSurfaceBrush.fromNode(node);
      expect(restored.step, 37.5);
      expect(restored.cells, brush.cells);
      restored.stampCell(1, 1);
      final changed = gridSurfaceReplacement(node, restored);
      expect(changed.id, node.id);
      expect(changed.surface!['moduleSize'], 37.5);
      expect(changed.properties, isEmpty);
      expect(validateDocument(d.copyWith(nodes: [changed])), isEmpty);
    },
  );
  test(
    'typed physical defaults allocate stable seats without style or manual aliases',
    () {
      final d = plan(), table = d.nodes.single;
      final first = reflowTable(d, table.id, 4);
      expect(validateDocument(first), isEmpty);
      final seats = first.nodes.where((n) => n.kind == 'seat').toList();
      expect(seats, hasLength(4));
      expect(
        seats.every((n) => n.width == 30 && n.height == 40 && n.style.isEmpty),
        isTrue,
      );
      expect(
        first.attachments.every(
          (a) =>
              a['placement']['mode'] == 'automatic' &&
              a['rotationMode'] == 'auto' &&
              !a.containsKey('manual'),
        ),
        isTrue,
      );
      final ids = seats.map((n) => n.id).toSet();
      final resized = resizeNode(first, table.id, 320, 200);
      expect(validateDocument(resized), isEmpty);
      expect(
        resized.nodes.where((n) => n.kind == 'seat').map((n) => n.id).toSet(),
        ids,
      );
      final styled = resized.copyWith(
        styles: {
          'label': {'size': 200, 'weight': 700},
        },
      );
      expect(
        styled.nodes.map((n) => n.toJson()),
        resized.nodes.map((n) => n.toJson()),
      );
    },
  );
  test('document defaults never infer a profile from existing mixed seats', () {
    final d = plan(), table = d.nodes.single;
    final mixed = d.copyWith(
      nodes: [
        table,
        LayoutNode(
          id: newLayoutId(),
          kind: 'seat',
          parentId: table.id,
          width: 99,
          height: 88,
        ),
      ],
    );
    expect(TableSeating.fromDocument(mixed, table).width, 30);
    expect(documentSeating(mixed).height, 40);
  });
  test('rigid move preserves local poses, placements, IDs and profiles', () {
    final d = reflowTable(plan(), plan().nodes.single.id, 4),
        table = d.nodes.firstWhere((n) => n.kind == 'table');
    final moved = transformNodes(d, {table.id}, dx: 50, dy: 10, rotation: 23);
    expect(validateDocument(moved), isEmpty);
    expect(moved.attachments, d.attachments);
    expect(
      moved.nodes.where((n) => n.kind == 'seat').map((n) => n.toJson()),
      d.nodes.where((n) => n.kind == 'seat').map((n) => n.toJson()),
    );
  });
  test(
    'moving a seat declares free placement; rotation declares independent manual rotation',
    () {
      final d = reflowTable(plan(), plan().nodes.single.id, 4),
          seat = d.nodes.firstWhere((n) => n.kind == 'seat');
      final moved = transformNodes(d, {seat.id}, dx: 5, dy: 5);
      expect(seatAttachment(moved, seat.id)!['placement'], {'mode': 'free'});
      expect(seatAttachment(moved, seat.id)!['rotationMode'], 'auto');
      final rotated = transformNodes(moved, {seat.id}, rotation: 17);
      expect(seatAttachment(rotated, seat.id)!['rotationMode'], 'manual');
      expect(validateDocument(rotated), isEmpty);
    },
  );
  test(
    'side pins are authoritative and resize a physical surface without growing for text',
    () {
      final d = reflowTable(plan(), plan().nodes.single.id, 2),
          seat = d.nodes.firstWhere((n) => n.kind == 'seat'),
          table = d.nodes.firstWhere((n) => n.kind == 'table');
      final pinned = d.copyWith(
        attachments: [
          for (final a in d.attachments)
            a['seatId'] == seat.id
                ? {
                    ...a,
                    'placement': {'mode': 'sidePinned', 'side': 'top', 't': .5},
                  }
                : a,
        ],
      );
      final resized = resizeNode(pinned, table.id, 320, 200),
          placed = resized.nodes.firstWhere((n) => n.id == seat.id);
      expect(placed.x, 0);
      expect(placed.y, -130);
      expect(seatAttachment(resized, seat.id)!['placement']['side'], 'top');
      expect(validateDocument(resized), isEmpty);
    },
  );
}
