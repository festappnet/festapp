import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

class MapLibreViewportController implements MapViewportController {
  final ml.MapController controller;
  final List<Completer<void>> _cameraWaiters = [];
  int _cameraRevision = 0;
  bool _invalidated = false;

  MapLibreViewportController(this.controller);

  static ml.Geographic _toGeographic(LatLng point) =>
      ml.Geographic(lon: point.longitude, lat: point.latitude);

  static LatLng _toLatLng(ml.Geographic point) => LatLng(point.lat, point.lon);

  @override
  MapCameraState get camera {
    final current = controller.getCamera();
    return MapCameraState(
      center: _toLatLng(current.center),
      zoom: current.zoom,
    );
  }

  @override
  double get directionLayoutZoom => controller.getCamera().zoom;

  @override
  Future<CameraApplyResult> applyCamera(CameraCommand command) async {
    var observedRevision = _cameraRevision;
    var attempts = 1;
    // Required navigation replaces older cosmetic camera transitions and
    // applies center and zoom as one command.
    if (command.transition == CameraTransition.animated) {
      await controller.animateCamera(
        center: _toGeographic(command.destination),
        zoom: command.zoom,
      );
    } else {
      await controller.moveCamera(
        center: _toGeographic(command.destination),
        zoom: command.zoom,
      );
    }
    var actual = camera;
    while (!_matches(command, actual) && !_invalidated && attempts < 3) {
      await _waitForCameraChange(observedRevision);
      observedRevision = _cameraRevision;
      actual = camera;
      if (_matches(command, actual) || _invalidated) break;
      attempts++;
      await controller.moveCamera(
        center: _toGeographic(command.destination),
        zoom: command.zoom,
      );
      actual = camera;
    }
    final applied = !_invalidated && _matches(command, actual);
    return CameraApplyResult(
      status: applied ? CameraApplyStatus.applied : CameraApplyStatus.retryable,
      surfaceId: command.surfaceId,
      command: command,
      actual: actual,
      reason: applied
          ? null
          : _invalidated
              ? 'surfaceInvalidated'
              : 'actualCameraMismatch',
    );
  }

  bool _matches(CameraCommand command, MapCameraState actual) {
    final centerMatches = const Distance().as(
          LengthUnit.Meter,
          actual.center,
          command.destination,
        ) <=
        command.centerToleranceMeters;
    final zoomMatches =
        (actual.zoom - command.zoom).abs() <= command.zoomTolerance;
    return centerMatches && zoomMatches;
  }

  Future<void> _waitForCameraChange(int observedRevision) {
    if (_invalidated || _cameraRevision != observedRevision) {
      return Future.value();
    }
    final waiter = Completer<void>();
    _cameraWaiters.add(waiter);
    return waiter.future;
  }

  /// Completes required camera commands only after MapLibre publishes actual
  /// native camera state. On iOS, moveCamera() can complete before getCamera()
  /// reflects the requested center and zoom.
  void notifyCameraChanged() {
    if (_invalidated) return;
    _cameraRevision++;
    final waiters = List<Completer<void>>.of(_cameraWaiters);
    _cameraWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  void invalidate() {
    if (_invalidated) return;
    _invalidated = true;
    final waiters = List<Completer<void>>.of(_cameraWaiters);
    _cameraWaiters.clear();
    for (final waiter in waiters) {
      if (!waiter.isCompleted) waiter.complete();
    }
  }

  @override
  Future<void> animateTo(
    LatLng destination, {
    double? zoom,
    Curve curve = Curves.easeInOut,
    Duration? duration,
  }) =>
      controller.animateCamera(
        center: _toGeographic(destination),
        zoom: zoom,
        nativeDuration: duration ?? const Duration(seconds: 2),
      );

  @override
  Future<void> fitCoordinates(
    List<LatLng> coordinates, {
    required EdgeInsets padding,
    Curve curve = Curves.easeInOut,
  }) {
    if (coordinates.isEmpty) return Future.value();
    return controller.fitBounds(
      bounds: ml.LngLatBounds.fromPoints(
        coordinates.map(_toGeographic).toList(growable: false),
      ),
      padding: padding,
    );
  }

  @override
  Offset coordinateToScreenPoint(LatLng coordinate) =>
      controller.toScreenLocation(_toGeographic(coordinate));

  @override
  LatLng screenPointToCoordinate(Offset point) =>
      _toLatLng(controller.toLngLat(point));
}
