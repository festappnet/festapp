import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

void main() {
  test(
    'default cell is a four-seat table module and joins full neighbouring cells',
    () {
      final brush = GridSurfaceBrush();
      brush.paint(205, 305);
      final first = brush.node(id: newLayoutId());
      expect(first.width, tableSurfaceModuleSize);
      expect(first.height, tableSurfaceModuleSize);
      expect(polygonSurfaceSlots(first), hasLength(4));
      expect(brush.paint(299, 399), false);
      brush.paint(405, 305);
      brush.paint(405, 505);
      final node = brush.node(id: first.id);
      final document = VenueLayoutDocument(nodes: [node]);
      expect(brush.cellCount, 5);
      expect(validateDocument(document), isEmpty);
      expect(hitTest(document, 250, 350), first.id);
      expect(hitTest(document, 350, 350), first.id);
      expect(hitTest(document, 450, 550), first.id);
      expect(hitTest(document, 250, 550), isNull);
    },
  );
  test(
    'brush retains the whole mouse trajectory, including a branch and retracing',
    () {
      final brush = GridSurfaceBrush(step: 8, diameter: 4);
      for (final p in [
        [200, 400],
        [200, 200],
        [400, 200],
        [400, 400],
        [400, 300],
        [550, 300],
      ]) {
        brush.paint(p[0].toDouble(), p[1].toDouble());
      }
      final n = brush.node(id: newLayoutId(), bar: true),
          d = VenueLayoutDocument(nodes: [n]);
      expect(validateDocument(d), isEmpty);
      expect(d.nodes, hasLength(1));
      for (final p in [
        [200, 300],
        [300, 200],
        [400, 350],
        [500, 300],
      ]) {
        expect(hitTest(d, p[0].toDouble(), p[1].toDouble()), n.id);
      }
      expect(hitTest(d, 300, 300), isNull);
      expect(hitTest(d, 500, 200), isNull);
      final count = brush.cellCount;
      expect(brush.paint(550, 300), false);
      expect(brush.cellCount, count);
    },
  );
  test(
    'closing a stroke preserves the unpainted hole in serialization, rendering and hits',
    () {
      final brush = GridSurfaceBrush(step: 8, diameter: 4);
      for (final p in [
        [200, 200],
        [500, 200],
        [500, 500],
        [200, 500],
        [200, 200],
      ]) {
        brush.paint(p[0].toDouble(), p[1].toDouble());
      }
      final n = brush.node(id: newLayoutId()),
          d = VenueLayoutDocument(nodes: [n]);
      expect(n.surface!['holes'], hasLength(1));
      expect(validateDocument(d), isEmpty);
      expect(hitTest(d, 350, 350), isNull);
      expect(hitTest(d, 200, 350), n.id);
      final item = (compileScene(d)['items'] as List).firstWhere(
        (i) => i['id'] == n.id,
      );
      expect((item['path'] as List).where((p) => p[0] == 'Z'), hasLength(2));
      expect(VenueLayoutDocument.fromJson(d.toJson()).toJson(), d.toJson());
      final bigger = resizeNode(d, n.id, n.width * 1.5, n.height * 1.5);
      expect(validateDocument(bigger), isEmpty);
      expect(hitTest(bigger, n.x, n.y), isNull);
      final invalid = n.copyWith(
        properties: {
          ...n.properties,
          'holes': [(n.surface!['holes'] as List).first.reversed.toList()],
        },
      );
      expect(validateDocument(d.copyWith(nodes: [invalid])), isNotEmpty);
    },
  );
  test(
    'brush clips to canvas and interpolates fast pointer motion without gaps',
    () {
      final brush = GridSurfaceBrush(
        step: 8,
        diameter: 8,
        clip: {'x': 0, 'y': 0, 'width': 800, 'height': 600},
      );
      brush.paint(0, 0);
      brush.paint(100000, 0);
      final n = brush.node(id: newLayoutId(), bar: true);
      expect(n.x - n.width / 2, 0);
      expect(n.x + n.width / 2, 800);
      expect(n.y - n.height / 2, 0);
      expect(hitTest(VenueLayoutDocument(nodes: [n]), 400, 8), n.id);
    },
  );
  test(
    'carriage seats face across each compartment, with a side corridor and end facilities',
    () {
      final d = compartmentLayout(), root = d.nodes.first;
      final left = d.nodes
          .where(
            (n) => n.properties['slot'].toString().startsWith('comp:0:row:0:'),
          )
          .toList();
      final right = d.nodes
          .where(
            (n) => n.properties['slot'].toString().startsWith('comp:0:row:1:'),
          )
          .toList();
      expect(left.map((n) => n.x).toSet(), hasLength(1));
      expect(right.map((n) => n.x).toSet(), hasLength(1));
      expect(left.map((n) => n.y).toSet(), hasLength(3));
      expect(left.first.rotation, 90);
      expect(right.first.rotation, 270);
      expect(
        d.nodes.where(
          (n) =>
              n.properties['slot'].toString().startsWith('decor:wc-') &&
              !n.properties['slot'].toString().endsWith(':label'),
        ),
        hasLength(2),
      );
      expect(layoutCollisions(d), isEmpty);
      expect(validateDocument(d), isEmpty);
      final grown = updateCompartmentLayout(d, root.id, compartments: 9);
      expect(
        grown.nodes.where((n) => n.kind == 'seat').map((n) => n.id),
        containsAll(d.nodes.where((n) => n.kind == 'seat').map((n) => n.id)),
      );
    },
  );
}
