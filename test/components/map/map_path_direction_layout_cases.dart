import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_direction_marker.dart';
import 'package:fstapp/components/map/map_path_direction_layout.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:latlong2/latlong.dart';

void main() {
  test('zoom controls visible direction density', () {
    const route = [
      LatLng(49.8200, 18.2600),
      LatLng(49.8300, 18.2700),
    ];

    final overview = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 12,
    );
    final detail = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 17,
    );

    expect(detail.length, greaterThan(overview.length));
  });

  test('a short two-point route still gets one direction marker', () {
    final directions = MapPathDirectionLayout.directions([
      _route(const [
        LatLng(49.8200, 18.2600),
        LatLng(49.8205, 18.2605),
      ]),
    ], zoom: 15);

    expect(directions, hasLength(1));
    expect(directions.single.bodyPixels, 16);
  });

  test('marker count depends on route length, not vertex density', () {
    const sparse = [
      LatLng(49.8200, 18.2600),
      LatLng(49.8300, 18.2700),
    ];
    const dense = [
      LatLng(49.8200, 18.2600),
      LatLng(49.8225, 18.2625),
      LatLng(49.8250, 18.2650),
      LatLng(49.8275, 18.2675),
      LatLng(49.8300, 18.2700),
    ];

    expect(
      MapPathDirectionLayout.directions([_route(dense)], zoom: 14),
      hasLength(
        MapPathDirectionLayout.directions([_route(sparse)], zoom: 14).length,
      ),
    );
  });

  test('long routes have a bounded number of markers', () {
    final directions = MapPathDirectionLayout.directions([
      _route(const [
        LatLng(49.80, 18.20),
        LatLng(49.90, 18.40),
      ]),
    ], zoom: 14);

    expect(directions, hasLength(12));
  });

  test('marker anchor never lands on a route vertex', () {
    const route = [
      LatLng(49.82, 18.26),
      LatLng(49.82, 18.265),
      LatLng(49.82, 18.27),
    ];

    final directions = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 12,
    );

    expect(directions, hasLength(1));
    expect(route, isNot(contains(directions.single.coordinate)));
  });

  test('creates renderer-neutral markers without changing the route', () {
    final route = MapPathPresentation(
      id: 'route',
      groupId: 7,
      points: const [
        LatLng(49.8200, 18.2600),
        LatLng(49.8300, 18.2700),
      ],
      colorValue: 0xff3366ff,
      strokeWidth: 3,
      kind: MapPathKind.main,
    );

    final directions = MapPathDirectionLayout.directions([route], zoom: 12);

    expect(directions, isNotEmpty);
    expect(directions.every((direction) => direction.groupId == 7), isTrue);
    expect(route.points, hasLength(2));
  });

  test('marker bearing points in route direction', () {
    final direction = MapPathDirectionLayout.directions([
      _route(const [
        LatLng(49.82, 18.26),
        LatLng(49.82, 18.27),
      ]),
    ], zoom: 14)
        .first;

    expect(direction.bearingDegrees, closeTo(90, 0.01));
  });

  test('direction glyph has a readable slender silhouette', () {
    final size = MapDirectionMarker.sizeFor(16);

    expect(size.width, lessThan(size.height));
    expect(size.height, 16);
  });

  test('marker anchor lies on the rendered route segment', () {
    const route = [
      LatLng(49.82, 18.26),
      LatLng(49.825, 18.27),
    ];
    final direction = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 14,
    ).first;
    final start = _mercator(route[0]);
    final end = _mercator(route[1]);
    final anchor = _mercator(direction.coordinate);
    final crossProduct = (end.$1 - start.$1) * (anchor.$2 - start.$2) -
        (end.$2 - start.$2) * (anchor.$1 - start.$1);

    expect(crossProduct, closeTo(0, 1e-12));
  });

  test('markers keep the same screen-space size at different zooms', () {
    const route = [
      LatLng(49.82, 18.26),
      LatLng(49.84, 18.28),
    ];
    final overview = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 12,
    ).first;
    final detail = MapPathDirectionLayout.directions(
      [_route(route)],
      zoom: 17,
    ).first;

    expect(overview.bodyPixels, detail.bodyPixels);
  });

  test('fit-scale route still produces visible direction markers', () {
    final directions = MapPathDirectionLayout.directions([
      _route(const [
        LatLng(49.80, 18.20),
        LatLng(49.8001, 18.2001),
        LatLng(49.82, 18.24),
        LatLng(49.8201, 18.2401),
      ]),
    ], zoom: 11);

    expect(directions, isNotEmpty);
  });

  test('dense straight route keeps markers after fit-scale simplification', () {
    final denseRoute = List.generate(
      101,
      (index) => LatLng(49.82, 18.26 + index * 0.0002),
      growable: false,
    );

    final directions = MapPathDirectionLayout.directions(
      [_route(denseRoute)],
      zoom: 11,
    );

    expect(directions, isNotEmpty);
  });
}

MapPathPresentation _route(List<LatLng> points) => MapPathPresentation(
      id: 'route',
      points: points,
      colorValue: 0xff3366ff,
      strokeWidth: 3,
      kind: MapPathKind.main,
    );

(double, double) _mercator(LatLng point) {
  final sinLatitude = math.sin(point.latitude * math.pi / 180);
  return (
    (point.longitude + 180) / 360,
    0.5 - math.log((1 + sinLatitude) / (1 - sinLatitude)) / (4 * math.pi),
  );
}
