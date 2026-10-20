import 'support/style.dart';
import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'round chair bodies and lounge backrests follow both authored dimensions',
    () {
      final id = newLayoutId();
      for (final style in ['round', 'roundUpholstered']) {
        List<Map> items(double width, double height) =>
            (compileScene(
                      VenueLayoutDocument(
                        nodes: [
                          LayoutNode(
                            id: id,
                            kind: 'seat',
                            width: width,
                            height: height,
                            properties: {},
                            style: {'seatStyle': style},
                          ),
                        ],
                      ),
                    )['items']
                    as List)
                .cast<Map>();
        final square = items(40, 40);
        expect(
          square.where((item) => item['path'] != null).length,
          style == 'round' ? 1 : 2,
        );
        for (final dimensions in [(80.0, 40.0), (40.0, 80.0)]) {
          final stretched = items(dimensions.$1, dimensions.$2);
          for (final original in square.where((item) => item['path'] != null)) {
            final before = original['path'] as List;
            final after =
                stretched.singleWhere(
                      (item) => item['id'] == original['id'],
                    )['path']
                    as List;
            expect(after.length, before.length);
            for (var i = 0; i < before.length; i++) {
              expect(after[i][0], before[i][0]);
              for (var j = 1; j < before[i].length; j++) {
                final scale = j.isOdd ? dimensions.$1 / 40 : dimensions.$2 / 40;
                expect(
                  after[i][j],
                  closeTo((before[i][j] as num) * scale, .004),
                  reason:
                      '$style ${original['id']} at $dimensions must stretch on both axes',
                );
              }
            }
          }
        }
      }
    },
  );
  test(
    'unconstrained round tables retain uniform angles at zero chair gap',
    () {
      for (final diameter in [180.0, 190.0, 200.0, 210.0, 240.0]) {
        for (final count in [5, 6, 7, 8, 9, 10]) {
          final source = tableLayout(
            shape: 'circle',
            width: diameter,
            height: diameter,
            count: count,
            x: 600,
            y: 600,
          );
          final table = source.nodes.first;
          final d = configureTableSeating(
            source,
            table.id,
            const TableSeating(gap: 0),
          );
          final seats = d.nodes.where((n) => n.kind == 'seat').toList();
          final angles =
              seats.map((n) => (atan2(n.y, n.x) + 2 * pi) % (2 * pi)).toList()
                ..sort();
          for (var i = 0; i < angles.length; i++) {
            final delta =
                (angles[(i + 1) % count] - angles[i] + 2 * pi) % (2 * pi);
            expect(
              delta,
              closeTo(2 * pi / count, .0001),
              reason: '$count seats, angles $angles',
            );
          }
          for (final seat in seats) {
            expect(
              sqrt(seat.x * seat.x + seat.y * seat.y),
              closeTo(diameter / 2 + 20, .003),
            );
          }
          expect(layoutCollisions(d), isEmpty);
        }
      }
    },
  );
  test(
    'zero gap places the visible lounge seat front at the tabletop edge',
    () {
      final source = tableLayout(
        shape: 'circle',
        width: 200,
        height: 200,
        count: 8,
        x: 600,
        y: 600,
      );
      final styled = withKindStyle(
        withLayoutMaterialFamily(source, 'lounge'),
        'seat',
        {'seatStyle': 'roundUpholstered'},
      );
      final d = configureTableSeating(
        styled,
        source.nodes.first.id,
        const TableSeating(gap: 0),
      );
      final items = compileScene(d)['items'] as List;
      for (final seat in d.nodes.where((node) => node.kind == 'seat')) {
        final body = items.firstWhere((item) => item['id'] == seat.id) as Map;
        final m = (body['matrix'] as List).cast<double>();
        final sx = m[4] - 600,
            sy = m[5] - 600,
            length = sqrt(sx * sx + sy * sy);
        final front = (body['path'] as List)
            .where((command) => command.first != 'Z')
            .map((command) {
              final world = transformPoint(
                m,
                (command[1] as num).toDouble(),
                (command[2] as num).toDouble(),
              );
              return ((world[0] - 600) * sx + (world[1] - 600) * sy) / length;
            })
            .reduce((double a, double b) => min(a, b));
        expect(
          front,
          closeTo(100, .05),
          reason: 'Visible front touches the tabletop at gap zero',
        );
      }
    },
  );
  test(
    'explicit reflow restores even spacing after pressure is removed',
    () {
      final source = tableLayout(
        shape: 'circle',
        width: 200,
        height: 200,
        count: 8,
        x: 600,
        y: 600,
      );
      final table = source.nodes.first;
      final blocker = LayoutNode(
        id: newLayoutId(),
        kind: 'shape',
        x: 732,
        y: 600,
        width: 40,
        height: 40,
        properties: {'obstacle': true},
      );
      final packed = configureTableSeating(
        source.copyWith(nodes: [...source.nodes, blocker]),
        table.id,
        const TableSeating(gap: 0),
      );
      expect(layoutCollisions(packed), isEmpty);
      List<double> gaps(VenueLayoutDocument d) {
        final angles =
            d.nodes
                .where((node) => node.kind == 'seat')
                .map((node) => (atan2(node.y, node.x) + 2 * pi) % (2 * pi))
                .toList()
              ..sort();
        return [
          for (var i = 0; i < angles.length; i++)
            (angles[(i + 1) % angles.length] - angles[i] + 2 * pi) % (2 * pi),
        ];
      }

      expect(gaps(packed).reduce(max), lessThanOrEqualTo(pi / 2 + .001));
      final free = packed.copyWith(
        nodes: packed.nodes.where((node) => node.id != blocker.id).toList(),
      );
      final restored = moveLayoutWithinCanvas(reflowTable(free,table.id,8),{table.id},dx:10);
      for (final gap in gaps(restored)) expect(gap, closeTo(pi / 4, .0001));
      expect(layoutCollisions(restored), isEmpty);
      expect(
        restored.nodes.map((node) => node.id).toSet(),
        source.nodes.map((node) => node.id).toSet(),
      );
    },
  );
}
