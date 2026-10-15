import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_locate_coordinator.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

final class _FakeViewportController implements MapViewportController {
  _FakeViewportController(this.camera);

  @override
  MapCameraState camera;

  final List<({LatLng destination, double? zoom})> animations = [];
  final List<CameraCommand> applications = [];

  @override
  double get directionLayoutZoom => camera.zoom;

  @override
  Future<void> animateTo(
    LatLng destination, {
    double? zoom,
    Curve curve = Curves.easeInOut,
    Duration? duration,
  }) async {
    animations.add((destination: destination, zoom: zoom));
  }

  @override
  Future<CameraApplyResult> applyCamera(CameraCommand command) async {
    applications.add(command);
    if (command.transition == CameraTransition.animated) {
      await animateTo(command.destination, zoom: command.zoom);
    }
    camera = MapCameraState(
      center: command.destination,
      zoom: command.zoom,
    );
    return CameraApplyResult(
      status: CameraApplyStatus.applied,
      surfaceId: command.surfaceId,
      command: command,
      actual: camera,
    );
  }

  @override
  Offset coordinateToScreenPoint(LatLng coordinate) =>
      throw UnimplementedError();

  @override
  Future<void> fitCoordinates(
    List<LatLng> coordinates, {
    required EdgeInsets padding,
    Curve curve = Curves.easeInOut,
  }) =>
      throw UnimplementedError();

  @override
  LatLng screenPointToCoordinate(Offset point) => throw UnimplementedError();
}

Position _position(double latitude, double longitude) => Position(
      longitude: longitude,
      latitude: latitude,
      timestamp: DateTime(2026),
      accuracy: 1,
      altitude: 0,
      altitudeAccuracy: 1,
      heading: 0,
      headingAccuracy: 1,
      speed: 0,
      speedAccuracy: 1,
    );

void main() {
  test('requires the active viewport to confirm the location camera change',
      () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    ));
    viewport.attach(surface);
    viewport.markReady();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async => _position(50.0755, 14.4378),
    );

    expect(
      await coordinator.recenter(isActive: () => true),
      MapLocateResult.recentered,
    );
    expect(surface.applications, hasLength(1));
    expect(surface.camera.center, const LatLng(50.0755, 14.4378));
    expect(surface.camera.zoom, 10);
    expect(
      surface.applications.single.transition,
      CameraTransition.animated,
    );
  });

  test('animates to the current position without changing the local zoom',
      () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    ));
    viewport.attach(surface);
    viewport.markReady();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async => _position(50.0755, 14.4378),
    );

    expect(
      await coordinator.recenter(isActive: () => true),
      MapLocateResult.recentered,
    );
    expect(surface.animations, hasLength(1));
    expect(
        surface.animations.single.destination, const LatLng(50.0755, 14.4378));
    expect(surface.animations.single.zoom, 10);
  });

  test('recenters from the displayed location without a second GPS request',
      () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    ));
    viewport.attach(surface);
    viewport.markReady();
    var requests = 0;
    final unresolvedPosition = Completer<Position?>();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () {
        requests++;
        return unresolvedPosition.future;
      },
    );

    expect(
      await coordinator
          .recenter(
            isActive: () => true,
            displayedLocation: const LatLng(49.8209, 18.2625),
          )
          .timeout(const Duration(milliseconds: 100)),
      MapLocateResult.recentered,
    );
    expect(requests, 0);
    expect(surface.camera.center, const LatLng(49.8209, 18.2625));
  });

  test('ignores a second recenter while the location request is in flight',
      () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 17,
    ));
    viewport.attach(surface);
    viewport.markReady();
    final position = Completer<Position?>();
    var requests = 0;
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () {
        requests++;
        return position.future;
      },
    );

    final first = coordinator.recenter(isActive: () => true);
    expect(coordinator.isLocating, isTrue);
    expect(
      await coordinator.recenter(isActive: () => true),
      MapLocateResult.ignored,
    );
    expect(requests, 1);

    position.complete(_position(50, 14));
    expect(await first, MapLocateResult.recentered);
    expect(coordinator.isLocating, isFalse);
    expect(surface.animations, hasLength(1));
    expect(surface.animations.single.zoom, 17);
  });

  test('preserves a useful zoom and caps it at the renderer limit', () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 24,
    ));
    viewport.attach(surface);
    viewport.markReady();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async => _position(50, 14),
    );

    await coordinator.recenter(isActive: () => true);

    expect(surface.animations.single.zoom, 22);
  });

  test('reports denied permission without moving the camera', () async {
    final viewport = MapViewportCoordinator();
    final surface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    ));
    viewport.attach(surface);
    viewport.markReady();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async => null,
    );

    expect(
      await coordinator.recenter(isActive: () => true),
      MapLocateResult.denied,
    );
    expect(surface.animations, isEmpty);
  });

  test('does not move either surface when the renderer changes while locating',
      () async {
    final viewport = MapViewportCoordinator();
    final firstSurface = _FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    ));
    viewport.attach(firstSurface);
    viewport.markReady();
    final position = Completer<Position?>();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () => position.future,
    );

    final recenter = coordinator.recenter(isActive: () => true);
    final secondSurface = _FakeViewportController(const MapCameraState(
      center: LatLng(1, 1),
      zoom: 12,
    ));
    viewport.attach(secondSurface);
    viewport.markReady();
    position.complete(_position(50, 14));

    expect(await recenter, MapLocateResult.ignored);
    expect(firstSurface.animations, isEmpty);
    expect(secondSurface.animations, isEmpty);
  });

  test('silently ignores denied permission from a stale surface', () async {
    final viewport = MapViewportCoordinator();
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    )));
    viewport.markReady();
    final position = Completer<Position?>();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () => position.future,
    );

    final recenter = coordinator.recenter(isActive: () => true);
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(1, 1),
      zoom: 12,
    )));
    viewport.markReady();
    position.complete(null);

    expect(await recenter, MapLocateResult.ignored);
  });

  test('silently ignores a location error from a stale surface', () async {
    final viewport = MapViewportCoordinator();
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    )));
    viewport.markReady();
    final position = Completer<Position?>();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () => position.future,
    );

    final recenter = coordinator.recenter(isActive: () => true);
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(1, 1),
      zoom: 12,
    )));
    viewport.markReady();
    position.completeError(StateError('stale location failure'));

    expect(await recenter, MapLocateResult.ignored);
  });

  test('does not request location before the active surface is ready',
      () async {
    final viewport = MapViewportCoordinator();
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    )));
    var requests = 0;
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async {
        requests++;
        return _position(50, 14);
      },
    );

    expect(
      await coordinator.recenter(isActive: () => true),
      MapLocateResult.ignored,
    );
    expect(requests, 0);
  });

  test('propagates location errors and leaves the action ready to retry',
      () async {
    final viewport = MapViewportCoordinator();
    viewport.attach(_FakeViewportController(const MapCameraState(
      center: LatLng(0, 0),
      zoom: 10,
    )));
    viewport.markReady();
    final coordinator = MapLocateCoordinator(
      viewport: viewport,
      currentPosition: () async => throw StateError('location unavailable'),
    );

    await expectLater(
      coordinator.recenter(isActive: () => true),
      throwsStateError,
    );
    expect(coordinator.isLocating, isFalse);
  });
}
