import 'dart:math';
import 'package:test/test.dart';
import 'package:venue_layout_core/venue_layout_core.dart';

LayoutNode line({
  double x = 100,
  double y = 127,
  String shape = 'line',
  List<List<double>>? points,
  double stroke = 1,
}) => LayoutNode(
  id: newLayoutId(),
  kind: 'shape',
  x: x,
  y: y,
  width: 100,
  height: 1,
  properties: {'shape': shape, 'points': ?points},
  style: {'strokeWidth': stroke},
);

void main() {
  test('thin line uses expanded broadphase across spatial cell boundaries', () {
    final n = line(), d = VenueLayoutDocument(nodes: [n]);
    expect(hitTest(d, 100, 134, tolerance: 8), n.id);
    expect(hitTest(d, 100, 135.1, tolerance: 8), isNull);
    expect(hitTest(d, 100, 129.9), n.id);
    expect(hitTest(d, 100, 130.1), isNull);
    expect(LayoutSpatialIndex(d).hitTest(100, 134, tolerance: 8), n.id);
  });

  test('line endpoint hit is radial rather than infinite extension', () {
    final n = line(), d = VenueLayoutDocument(nodes: [n]);
    expect(hitTest(d, 156, 127, tolerance: 8), n.id);
    expect(hitTest(d, 159, 127, tolerance: 8), isNull);
    expect(hitTest(d, 156, 133, tolerance: 8), isNull);
  });

  test('diagonal segments and open polyline never hit a filled triangle', () {
    final n = line(
          shape: 'polyline',
          x: 200,
          y: 200,
          points: [
            [-50, 50],
            [0, -50],
            [50, 50],
          ],
        ),
        d = VenueLayoutDocument(nodes: [n]);
    expect(hitTest(d, 176, 200, tolerance: 3), n.id);
    expect(hitTest(d, 200, 215, tolerance: 8), isNull);
    expect(hitTest(d, 200, 250, tolerance: 8), isNull);
    // Actual path points can exceed the nominal width/height fields.
    final extended = line(
          points: [
            [0, 0],
            [400, 400],
          ],
        ),
        extendedDoc = VenueLayoutDocument(nodes: [extended]);
    expect(hitTest(extendedDoc, 400, 427, tolerance: 2), extended.id);
    expect(hitTest(extendedDoc, 400, 440, tolerance: 2), isNull);
  });

  test('screen radius remains consistent at different zoom levels', () {
    final n = line(), d = VenueLayoutDocument(nodes: [n]);
    for (final zoom in [.25, 1.0, 4.0]) {
      expect(hitTest(d, 100, 127 + 7 / zoom, tolerance: 8 / zoom), n.id);
      expect(hitTest(d, 100, 127 + 9 / zoom, tolerance: 8 / zoom), isNull);
    }
  });

  test('nested rotation transforms pointer into the actual line frame', () {
    final root = LayoutNode(
      id: newLayoutId(),
      kind: 'group',
      x: 200,
      y: 200,
      rotation: 37,
    );
    final n = line(x: 0, y: 0).copyWith(parentId: root.id),
        d = VenueLayoutDocument(nodes: [root, n]),
        angle = 37 * pi / 180;
    expect(
      hitTest(d, 200 - sin(angle) * 7, 200 + cos(angle) * 7, tolerance: 8),
      n.id,
    );
    expect(
      hitTest(d, 200 - sin(angle) * 9, 200 + cos(angle) * 9, tolerance: 8),
      isNull,
    );
  });

  test('arrowhead strokes and physical stroke thickness are selectable', () {
    final arrow = line(shape: 'arrow'), d = VenueLayoutDocument(nodes: [arrow]);
    // This lies on the arrowhead, over three units away from the shaft.
    expect(
      hitTest(d, 150 - 10 * cos(.5), 127 + 10 * sin(.5), tolerance: .1),
      arrow.id,
    );
    final thick = line(stroke: 30),
        thickDoc = VenueLayoutDocument(nodes: [thick]);
    expect(hitTest(thickDoc, 100, 141, tolerance: 2), thick.id);
    expect(hitTest(thickDoc, 100, 143, tolerance: 2), isNull);
  });

  test('filled shapes keep exact semantics and topmost paint order', () {
    final n = line(),
        rectangle = LayoutNode(
          id: newLayoutId(),
          kind: 'shape',
          x: 100,
          y: 127,
          width: 30,
          height: 30,
          z: 1,
        );
    final d = VenueLayoutDocument(nodes: [n, rectangle]);
    expect(hitTest(d, 100, 127, tolerance: 8), rectangle.id);
    expect(hitTest(d, 120, 133, tolerance: 8), n.id);
    expect(
      hitTest(VenueLayoutDocument(nodes: [rectangle]), 120, 127, tolerance: 8),
      isNull,
    );
    for (final invalid in [-1.0, double.nan, double.infinity]) {
      expect(
        () => hitTest(d, 100, 127, tolerance: invalid),
        throwsArgumentError,
      );
    }
  });
}
