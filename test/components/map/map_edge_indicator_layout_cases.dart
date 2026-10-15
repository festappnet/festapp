import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_edge_indicator_layout.dart';

void main() {
  const viewport = Size(400, 800);
  const topObstacle = Rect.fromLTRB(0, 0, 400, 100);
  const bottomObstacle = Rect.fromLTRB(100, 680, 300, 800);
  const obstacles = [topObstacle, bottomObstacle];

  test('returns no edge placement while the user is visible', () {
    expect(
      MapEdgeIndicatorLayout.resolve(
        target: const Offset(200, 400),
        viewport: viewport,
        occupiedRects: obstacles,
      ),
      isNull,
    );
  });

  test('shows the indicator when a control hides an in-viewport user', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(200, 50),
      viewport: viewport,
      occupiedRects: obstacles,
    )!;

    expect(placement.edgeTip, const Offset(200, 100));
  });

  test('projects an eastern user onto the right edge and points east', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(900, 390),
      viewport: viewport,
      occupiedRects: obstacles,
      indicatorTipLength: 16,
    )!;

    expect(placement.edgeTip.dx, 400);
    expect(placement.edgeTip.dy, 390);
    expect(placement.center.dx, 384);
    expect(placement.center.dy, 390);
    expect(placement.rotationRadians, closeTo(-math.pi / 2, 0.001));
  });

  test('projects a north-western user onto the matching edge direction', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(-400, -400),
      viewport: viewport,
      occupiedRects: obstacles,
      indicatorTipLength: 16,
    )!;

    expect(placement.edgeTip.dx, 0);
    expect(placement.edgeTip.dy, closeTo(126.667, 0.001));
    expect(placement.center.dx, greaterThan(0));
    expect(placement.center.dy, greaterThan(placement.edgeTip.dy));
    expect(placement.rotationRadians, lessThan(-math.pi / 2));
  });

  test('uses the inner top rail when controls occupy the physical edge', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(105.1, -221.4),
      viewport: const Size(402, 666),
      occupiedRects: const [
        Rect.fromLTWH(8, 8, 386, 104),
        Rect.fromLTWH(194, 8, 200, 28),
      ],
      indicatorClearance: 22,
    )!;

    expect(placement.edgeTip.dx, closeTo(157.5, 0.1));
    expect(placement.edgeTip.dy, 112);
  });

  test('ignores a nested control edge inside a larger occupied area', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(406, -190.3),
      viewport: const Size(402, 666),
      occupiedRects: const [
        Rect.fromLTWH(8, 8, 386, 104),
        Rect.fromLTWH(194, 8, 200, 28),
      ],
      indicatorClearance: 22,
    )!;

    expect(placement.edgeTip.dx, closeTo(299, 0.1));
    expect(placement.edgeTip.dy, 112);
  });

  test('moves continuously along the inner bottom rail', () {
    final tips = <double>[160, 180, 200, 220, 240]
        .map(
          (x) => MapEdgeIndicatorLayout.resolve(
            target: Offset(x, 1200),
            viewport: viewport,
            occupiedRects: obstacles,
            indicatorTipLength: 16,
            indicatorClearance: 16,
          )!
              .edgeTip,
        )
        .toList();

    expect(tips.map((tip) => tip.dy), everyElement(680));
    for (var index = 1; index < tips.length; index++) {
      expect(tips[index].dx, greaterThan(tips[index - 1].dx));
    }
  });

  test('uses the inner perimeter when controls occupy every physical edge', () {
    final placement = MapEdgeIndicatorLayout.resolve(
      target: const Offset(900, 390),
      viewport: viewport,
      occupiedRects: const [
        Rect.fromLTRB(0, 0, 400, 50),
        Rect.fromLTRB(0, 750, 400, 800),
        Rect.fromLTRB(0, 0, 50, 800),
        Rect.fromLTRB(350, 0, 400, 800),
      ],
    )!;

    expect(placement.edgeTip.dx, 350);
    expect(placement.edgeTip.dy, closeTo(397.86, 0.01));
  });

  test('keeps both bottom-corner transitions continuous without extra gap', () {
    const mobileViewport = Size(402, 666);
    const bottomControl = Rect.fromLTWH(43, 604, 316, 46);
    const center = Offset(201, 333);
    final tips = <Offset>[];
    for (var step = 0; step <= 180; step++) {
      final angle = 0.65 + step * 0.01;
      final target = center + Offset(math.cos(angle), math.sin(angle)) * 1200;
      tips.add(
        MapEdgeIndicatorLayout.resolve(
          target: target,
          viewport: mobileViewport,
          occupiedRects: const [bottomControl],
          indicatorClearance: 22,
        )!
            .edgeTip,
      );
    }

    for (var index = 1; index < tips.length; index++) {
      expect((tips[index] - tips[index - 1]).distance, lessThan(8));
    }
    final south = MapEdgeIndicatorLayout.resolve(
      target: const Offset(201, 1200),
      viewport: mobileViewport,
      occupiedRects: const [bottomControl],
      indicatorClearance: 22,
    )!;
    expect(south.edgeTip.dy, bottomControl.top);
  });

  test('rejects projections that cannot represent a direction', () {
    expect(
      MapEdgeIndicatorLayout.resolve(
        target: const Offset(double.nan, 1),
        viewport: viewport,
        occupiedRects: obstacles,
      ),
      isNull,
    );
  });
}
