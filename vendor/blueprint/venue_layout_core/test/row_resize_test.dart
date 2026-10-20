import 'dart:math' as math;
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  for (final arc in [0.0, 7.0, -7.0]) {
    test(
      'row resize arc $arc preserves identities footprints styles and target bounds',
      () {
        var document = rowLayout(rows: 3, seatsPerRow: 6, blocks: 2, arc: arc);
        final root = document.nodes.first, seat = document.nodes[1];
        document = document.copyWith(
          nodes: document.nodes
              .map(
                (n) => n.id == root.id
                    ? n.copyWith(rotation: 37)
                    : n.id == seat.id
                    ? n.copyWith(
                        width: 44,
                        height: 36,
                        properties: {...n.properties},
                        style: {
                          'fill': '#123456FF',
                          'label': {'size': 14},
                        },
                      )
                    : n,
              )
              .toList(),
        );
        final before = rowAssemblyBounds(document, root.id),
            result = resizeRowAssembly(
              document,
              root.id,
              before['width']! + 100,
              before['height']! + 60,
            ),
            after = rowAssemblyBounds(result, root.id);
        expect(after['width'], closeTo(before['width']! + 100, 1));
        expect(after['height'], closeTo(before['height']! + 60, 1));
        expect(result.nodes.map((n) => n.id), document.nodes.map((n) => n.id));
        for (final old in document.nodes.where((n) => n.kind == 'seat')) {
          final next = result.nodes.firstWhere((n) => n.id == old.id);
          expect(next.width, old.width);
          expect(next.height, old.height);
          expect(next.properties, old.properties);
        }
        final nextRoot = result.nodes.firstWhere((n) => n.id == root.id);
        expect(
          [nextRoot.x, nextRoot.y, nextRoot.rotation],
          [root.x, root.y, 37],
        );
        final parameters = rowLayoutParameters(result, root.id);
        for (final n in result.nodes.where((n) => n.kind == 'seat')) {
          final slot = '${n.properties['slot']}'
                  .split(':')
                  .map(int.parse)
                  .toList(),
              half = (parameters['seatsPerRow']! - 1) / 2;
          expect(
            n.x,
            closeTo(
              slot[1] *
                      (parameters['seatsPerRow']! * parameters['spacing']! +
                          parameters['aisle']!) +
                  slot[2] * parameters['spacing']!,
              .001,
            ),
          );
          expect(
            n.rotation,
            closeTo(
              math.atan(
                    2 *
                        parameters['arc']! *
                        (slot[2] - half) /
                        parameters['spacing']!,
                  ) *
                  180 /
                  math.pi,
              .001,
            ),
          );
        }
        expect(layoutCollisions(result), isEmpty);
        expect(validateDocument(result), isEmpty);
      },
    );
    test(
      'row resize arc $arc clamps tiny requests without collapsing chairs',
      () {
        final document = rowLayout(
              rows: 3,
              seatsPerRow: 6,
              blocks: 2,
              arc: arc,
            ),
            root = document.nodes.first,
            result = resizeRowAssembly(document, root.id, 1, 1);
        expect(result.nodes.where((n) => n.kind == 'seat').length, 36);
        expect(
          result.nodes
              .where((n) => n.kind == 'seat')
              .every((n) => n.width == 40 && n.height == 40),
          isTrue,
        );
        expect(layoutCollisions(result), isEmpty);
        expect(validateDocument(result), isEmpty);
      },
    );
  }
  test(
    'row bounds independent of rotated ancestry and ignore placeholder root box',
    () {
      final document = rowLayout(rows: 2, seatsPerRow: 4, arc: 6),
          root = document.nodes.first,
          parent = LayoutNode(
            id: newLayoutId(),
            kind: 'group',
            x: 700,
            y: 300,
            rotation: 63,
          ),
          nested = document.copyWith(
            nodes: [
              parent,
              ...document.nodes.map(
                (n) => n.id == root.id
                    ? n.copyWith(
                        parentId: parent.id,
                        rotation: 37,
                        width: 9999,
                        height: 9999,
                      )
                    : n,
              ),
            ],
          );
      final a = rowAssemblyBounds(document, root.id),
          b = rowAssemblyBounds(nested, root.id);
      for (final key in ['x', 'y', 'width', 'height']) {
        expect(b[key], closeTo(a[key]!, .001));
      }
    },
  );
  test(
    'locked subtree or ancestor blocks whole resize and invalid requests reject',
    () {
      final document = rowLayout(rows: 2, seatsPerRow: 4),
          root = document.nodes.first,
          locked = document.copyWith(
            nodes: document.nodes
                .map((n) => n.kind == 'seat' ? n.copyWith(locked: true) : n)
                .toList(),
          );
      expect(
        () => resizeRowAssembly(locked, root.id, 900, 500),
        throwsStateError,
      );
      expect(
        () => resizeRowAssembly(document, root.id, double.infinity, 500),
        throwsArgumentError,
      );
      expect(
        () => resizeRowAssembly(document, root.id, 500, -1),
        throwsArgumentError,
      );
    },
  );
  test(
    'single chair cannot resize its footprint and manual override survives',
    () {
      final single = rowLayout(rows: 1, seatsPerRow: 1),
          resized = resizeRowAssembly(single, single.nodes.first.id, 900, 500);
      expect(rowAssemblyBounds(resized, single.nodes.first.id)['width'], 40);
      expect(rowAssemblyBounds(resized, single.nodes.first.id)['height'], 40);
      var document = rowLayout(rows: 2, seatsPerRow: 4);
      final seat = document.nodes[1];
      document = document.copyWith(
        nodes: document.nodes
            .map(
              (n) => n.id == seat.id
                  ? n.copyWith(x: -150, properties: n.properties)
                  : n,
            )
            .toList(),
      );
      document = document.copyWith(
        attachments: [
          for (final a in document.attachments)
            a['seatId'] == seat.id
                ? {
                    ...a,
                    'placement': {'mode': 'free'},
                  }
                : a,
        ],
      );
      final before = rowAssemblyBounds(document, document.nodes.first.id),
          result = resizeRowAssembly(
            document,
            document.nodes.first.id,
            before['width']! + 100,
            before['height']! + 60,
          );
      expect(
        result.nodes.firstWhere((n) => n.id == seat.id).toJson(),
        document.nodes.firstWhere((n) => n.id == seat.id).toJson(),
      );
    },
  );
  test(
    'unchanged requested bounds are an exact no-op and strong arcs clamp safely',
    () {
      for (final arc in [0.0, 20.0, -20.0, 80.0]) {
        final document = rowLayout(
              rows: 3,
              seatsPerRow: 6,
              blocks: 2,
              arc: arc,
            ),
            root = document.nodes.first,
            bounds = rowAssemblyBounds(document, root.id);
        expect(
          resizeRowAssembly(
            document,
            root.id,
            bounds['width']!,
            bounds['height']!,
          ),
          same(document),
        );
        final tiny = resizeRowAssembly(document, root.id, 1, 1);
        expect(layoutCollisions(tiny), isEmpty);
      }
    },
  );
}
