import 'package:flutter/widgets.dart';
import 'package:latlong2/latlong.dart';

class MapCameraState {
  final LatLng center;
  final double zoom;

  const MapCameraState({required this.center, required this.zoom});
}

enum CameraApplyStatus { applied, retryable, rejected, staleSurface }

enum CameraTransition { immediate, animated }

final class CameraCommand {
  final String surfaceId;
  final LatLng destination;
  final double zoom;
  final double centerToleranceMeters;
  final double zoomTolerance;
  final CameraTransition transition;

  const CameraCommand({
    required this.surfaceId,
    required this.destination,
    required this.zoom,
    this.centerToleranceMeters = 3,
    this.zoomTolerance = 0.05,
    this.transition = CameraTransition.immediate,
  });
}

final class CameraApplyResult {
  final CameraApplyStatus status;
  final String surfaceId;
  final CameraCommand command;
  final MapCameraState? actual;
  final String? reason;

  const CameraApplyResult({
    required this.status,
    required this.surfaceId,
    required this.command,
    this.actual,
    this.reason,
  });

  bool get isApplied => status == CameraApplyStatus.applied;
}

/// Camera contract used by page-level feature logic, independent of the
/// concrete map renderer.
abstract interface class MapViewportController {
  MapCameraState get camera;

  /// Zoom normalized to MapLibre's 512px world-tile convention.
  double get directionLayoutZoom;

  /// Establishes and verifies required navigation state against actual camera.
  Future<CameraApplyResult> applyCamera(CameraCommand command);

  Future<void> animateTo(
    LatLng destination, {
    double? zoom,
    Curve curve = Curves.easeInOut,
    Duration? duration,
  });

  Future<void> fitCoordinates(
    List<LatLng> coordinates, {
    required EdgeInsets padding,
    Curve curve = Curves.easeInOut,
  });

  Offset coordinateToScreenPoint(LatLng coordinate);

  LatLng screenPointToCoordinate(Offset point);
}

/// Stable controller owned by MapPage. A renderer surface attaches its own
/// adapter without exposing the concrete controller to feature logic.
class MapViewportCoordinator implements MapViewportController {
  MapViewportController? _delegate;
  bool _isReady = false;
  int _surfaceEpoch = 0;
  int _readinessEpoch = 0;

  String get surfaceId => 'map-surface-$_surfaceEpoch';
  int get readinessEpoch => _readinessEpoch;

  bool get isAttached => _delegate != null;
  bool get isReady => isAttached && _isReady;

  void attach(MapViewportController controller) {
    _delegate = controller;
    _isReady = false;
    _surfaceEpoch++;
    _readinessEpoch++;
  }

  void markReady() {
    if (_delegate != null && !_isReady) {
      _isReady = true;
      _readinessEpoch++;
    }
  }

  void detach(MapViewportController controller) {
    if (identical(_delegate, controller)) {
      _delegate = null;
      _isReady = false;
      _readinessEpoch++;
    }
  }

  MapViewportController get _active =>
      _delegate ??
      (throw StateError('The map viewport is not attached to a surface.'));

  @override
  MapCameraState get camera => _active.camera;

  @override
  double get directionLayoutZoom => _active.directionLayoutZoom;

  @override
  Future<CameraApplyResult> applyCamera(CameraCommand command) async {
    final delegate = _delegate;
    final token = surfaceId;
    if (delegate == null || !_isReady) {
      return CameraApplyResult(
        status: CameraApplyStatus.retryable,
        surfaceId: token,
        command: command,
        reason: 'surfaceNotReady',
      );
    }
    if (command.surfaceId != token) {
      return CameraApplyResult(
        status: CameraApplyStatus.staleSurface,
        surfaceId: token,
        command: command,
        reason: 'surfaceChangedBeforeCommand',
      );
    }
    final result = await delegate.applyCamera(command);
    if (!identical(delegate, _delegate) || token != surfaceId) {
      return CameraApplyResult(
        status: CameraApplyStatus.staleSurface,
        surfaceId: surfaceId,
        command: command,
        actual: result.actual,
        reason: 'surfaceChangedDuringCommand',
      );
    }
    return result;
  }

  @override
  Future<void> animateTo(
    LatLng destination, {
    double? zoom,
    Curve curve = Curves.easeInOut,
    Duration? duration,
  }) =>
      _active.animateTo(
        destination,
        zoom: zoom,
        curve: curve,
        duration: duration,
      );

  @override
  Future<void> fitCoordinates(
    List<LatLng> coordinates, {
    required EdgeInsets padding,
    Curve curve = Curves.easeInOut,
  }) =>
      _active.fitCoordinates(
        coordinates,
        padding: padding,
        curve: curve,
      );

  @override
  Offset coordinateToScreenPoint(LatLng coordinate) =>
      _active.coordinateToScreenPoint(coordinate);

  @override
  LatLng screenPointToCoordinate(Offset point) =>
      _active.screenPointToCoordinate(point);
}
