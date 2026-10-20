import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

LayoutNode table(double x, double y, {double width = 100}) => LayoutNode(
  surface: const {'type': 'rect'},
  id: newLayoutId(),
  kind: 'table',
  x: x,
  y: y,
  width: width,
  height: 60,
);
VenueLayoutDocument scene(List<LayoutNode> nodes) => VenueLayoutDocument(
  nodes: nodes,
  canvas: {'x': 0, 'y': 0, 'width': 2000, 'height': 1200, 'fill': '#FFFFFFFF'},
);

void main() {
  test('continues equal body gaps in a table row with spacing guide', () {
    final moving = table(490, 100);
    final d = scene([table(100, 100), table(300, 100), moving]);
    final snap = snapTranslation(d, {moving.id}, 6, 0);
    expect(snap.dx, 10);
    expect(snap.guides, contains(containsPair('kind', 'spacing')));
    expect(
      snap.guides.firstWhere((g) => g['kind'] == 'spacing')['spacing'],
      100,
    );
    expect(snap.magnet, startsWith('spacing:'));
  });

  test('equal insertion gaps and different table widths use body edges', () {
    final moving = table(296, 100, width: 80);
    final d = scene([table(100, 100, width: 120), table(500, 100), moving]);
    final snap = snapTranslation(d, {moving.id}, 0, 0, zoom: .5);
    // Available interval is [160,450], leaving 105 on both sides.
    expect(snap.dx, 9);
    // Nine units is outside the normal threshold; zooming out makes the same
    // visible distance eligible without changing world geometry.
  });

  test('continues equal gaps vertically and from the beginning of a row', () {
    final column = table(100, 490);
    final d = scene([table(100, 100), table(100, 300), column]);
    final snap = snapTranslation(d, {column.id}, 0, 6);
    expect(snap.dy, 10);
    final before = table(110, 100);
    final row = scene([table(300, 100), table(500, 100), before]);
    expect(snapTranslation(row, {before.id}, -6, 0).dx, -10);
  });

  test('spacing ignores distant rows and occupied continuation cells', () {
    final moving = table(490, 250);
    final d = scene([table(100, 100), table(300, 100), moving]);
    expect(snapTranslation(d, {moving.id}, 6, 0).dx, 6);
    final sameRow = table(490, 100);
    final blocked = scene([
      table(100, 100),
      table(300, 100),
      table(520, 100),
      sameRow,
    ]);
    final result = snapTranslation(blocked, {sameRow.id}, 6, 0);
    expect(result.guides.where((g) => g['kind'] == 'spacing'), isEmpty);
  });

  test(
    'spacing threshold scales with zoom and Alt bypass preserves raw motion',
    () {
      final moving = table(490, 100);
      final d = scene([table(100, 100), table(300, 100), moving]);
      expect(snapTranslation(d, {moving.id}, 6, 0, zoom: 2).dx, 6);
      final free = snapTranslation(
        d,
        {moving.id},
        6,
        0,
        grid: 8,
        disabled: true,
      );
      expect(free.dx, 6);
      expect(free.guides, isEmpty);
    },
  );

  test('regular row snapping works in a rotated parent coordinate frame', () {
    final group = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      x: 800,
      y: 400,
      rotation: 30,
    );
    final moving = table(490, 0).copyWith(parentId: group.id);
    final d = scene([
      group,
      table(100, 0).copyWith(parentId: group.id),
      table(300, 0).copyWith(parentId: group.id),
      moving,
    ]);
    final snap = snapTranslation(
      d,
      {moving.id},
      6 * cos(pi / 6),
      6 * sin(pi / 6),
      axisRotation: 30,
    );
    expect(snap.dx, closeTo(10 * cos(pi / 6), .002));
    expect(snap.dy, closeTo(10 * sin(pi / 6), .002));
    expect(snap.guides, contains(containsPair('kind', 'spacing')));
  });

  test(
    'grid gently catches near a line without quantizing ordinary motion',
    () {
      final moving = table(490, 250);
      final d = scene([moving]);
      // Body left is 440. Eight-unit grid: 442 stays free; 441 catches 440.
      expect(snapTranslation(d, {moving.id}, 2, 0, grid: 8).dx, 2);
      expect(snapTranslation(d, {moving.id}, 1, 0, grid: 8).dx, 0);
      expect(snapTranslation(d, {moving.id}, 1, 0, grid: 8, zoom: 4).dx, 1);
    },
  );
}
