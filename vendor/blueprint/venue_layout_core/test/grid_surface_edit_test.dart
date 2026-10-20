import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final bar in [false, true]) {
    final step = bar ? barSurfaceModuleSize : tableSurfaceModuleSize;
    test(
      'seed/extend/erase uses the painting grid for ${bar ? 'bar' : 'table'}',
      () {
        final brush = GridSurfaceBrush(
          step: step,
          originX: -step,
          originY: -step,
          seedCells: [(0, 0), (1, 0), (0, 1), (1, 1)],
        );
        final node = brush
            .node(id: newLayoutId(), bar: bar)
            .copyWith(
              x: 500,
              y: 500,
              rotation: 30,
              label: 'Keep',
              seating: const TableSeating().record,
              properties: {
                ...brush.node(id: newLayoutId(), bar: bar).properties,
              },
              style: {'fill': '#123456FF'},
            );
        final document = VenueLayoutDocument(nodes: [node]);
        final expanded = extendGridTableSurface(
          document,
          node.id,
          1,
          step * 2,
          step * .4,
        );
        final next = expanded.nodes.single;
        final painted = GridSurfaceBrush(
          step: step,
          originX: -step,
          originY: -step,
          seedCells: brush.cells,
        )..stampCell(2, 0);
        final expected = gridSurfaceReplacement(node, painted);
        expect(next.toJson(), expected.toJson());
        expect(next.label, 'Keep');
        expect(next.rotation, 30);
        expect(next.style['fill'], '#123456FF');
        expect(GridSurfaceBrush.fromNode(next).cellCount, 5);
        final inset = extendGridTableSurface(
          document,
          node.id,
          1,
          0,
          step * .4,
        );
        final erased = GridSurfaceBrush(
          step: step,
          originX: -step,
          originY: -step,
          seedCells: brush.cells,
        )..stampCell(1, 0, erase: true);
        expect(
          inset.nodes.single.toJson(),
          gridSurfaceReplacement(node, erased).toJson(),
        );
        expect(validateDocument(inset), isEmpty);
      },
    );
  }

  test('erase preserves holes and rejects disconnected or empty surfaces', () {
    final brush = GridSurfaceBrush(
      seedCells: [
        for (var y = 0; y < 3; y++)
          for (var x = 0; x < 3; x++) (x, y),
      ],
    );
    brush.stampCell(1, 1, erase: true);
    final ring = brush.node(id: newLayoutId());
    expect(ring.surface!['holes'], hasLength(1));
    expect(GridSurfaceBrush.fromNode(ring).cellCount, 8);
    final disconnected = GridSurfaceBrush(seedCells: [(0, 0), (1, 0), (2, 0)]);
    disconnected.stampCell(1, 0, erase: true);
    expect(() => disconnected.node(id: newLayoutId()), throwsStateError);
    final empty = GridSurfaceBrush(seedCells: [(0, 0)])
      ..stampCell(0, 0, erase: true);
    expect(() => empty.node(id: newLayoutId()), throwsStateError);
  });

  test('independent stamps never create interpolated connecting cells', () {
    final brush = GridSurfaceBrush(seedCells: [(0, 0), (1, 0), (2, 0)]);
    brush.paint(50, 50);
    brush.resetStroke();
    brush.paint(250, 50, erase: true);
    expect(brush.cells, {(0, 0), (1, 0)});
  });

  test('custom resize and L preset retain fixed modules including holes', () {
    final base = LayoutNode(
      surface: const {'type': 'rect'},
      id: newLayoutId(),
      kind: 'table',
      width: 190,
      height: 110,
    );
    final l = snapTableSurfaceToGrid(base, preset: 'L');
    expect(l.width, 200);
    expect(l.height, 200);
    expect(GridSurfaceBrush.fromNode(l).cellCount, 3);
    final resized = snapTableSurfaceToGrid(l, width: 355, height: 290);
    expect(resized.width, 400);
    expect(resized.height, 300);
    expect(GridSurfaceBrush.fromNode(resized).cellCount, greaterThan(3));
    final imported = l.copyWith(width: 210);
    expect(() => GridSurfaceBrush.fromNode(imported), throwsStateError);
  });
  test('grid resize retains protected seat rejection', () {
    var doc = tableLayout(shape: 'rect', width: 300, height: 300, count: 8);
    final table = doc.nodes.firstWhere((n) => n.kind == 'table');
    doc = doc.copyWith(
      nodes: [
        for (final n in doc.nodes)
          n.id == table.id
              ? n.copyWith(
                  properties: {
                    ...n.properties,
                    'shape': 'polygon',
                    'points': surfacePresetPoints('rectangle', 300, 300),
                  },
                )
              : n,
      ],
    );
    final protected = doc.nodes
        .where((n) => n.kind == 'seat')
        .map((n) => n.id)
        .toSet();
    expect(
      () => resizeGridTableSurface(
        doc,
        table.id,
        100,
        100,
        protectedSeatIds: protected,
      ),
      throwsA(isA<TableResizeRejected>()),
    );
  });
  test(
    'first and last boundary cells match individually painted/erased modules',
    () {
      for (final bar in [false, true]) {
        final step = bar ? barSurfaceModuleSize : tableSurfaceModuleSize;
        final brush = GridSurfaceBrush(
          step: step,
          originX: -step,
          originY: -2 * step,
          seedCells: [
            for (var y = 0; y < 4; y++)
              for (var x = 0; x < 2; x++) (x, y),
          ],
        );
        final raw = brush.node(id: newLayoutId(), bar: bar);
        final node = raw.copyWith(seating: const TableSeating().record);
        final doc = VenueLayoutDocument(nodes: [node]);
        for (final cell in [0, 3]) {
          for (final erase in [false, true]) {
            final changed = extendGridTableSurface(
              doc,
              node.id,
              1,
              erase ? 0 : step * 2,
              step * 99,
              cellIndex: cell,
            );
            final expected = GridSurfaceBrush(
              step: step,
              originX: -step,
              originY: -2 * step,
              seedCells: brush.cells,
            )..stampCell(erase ? 1 : 2, cell, erase: erase);
            expect(
              changed.nodes.single.toJson(),
              gridSurfaceReplacement(node, expected).toJson(),
            );
          }
        }
      }
    },
  );
}
