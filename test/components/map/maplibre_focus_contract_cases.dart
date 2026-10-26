import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:fstapp/components/map/maplibre/maplibre_viewport_controller.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;

void main() {
  test('MapLibre confirms required focus from its actual camera', () async {
    final native = _FakeMapLibreController();
    final viewport = MapLibreViewportController(native);
    const command = CameraCommand(
      surfaceId: 'native-1',
      destination: LatLng(49.835, 18.292),
      zoom: 18,
    );

    final result = await viewport.applyCamera(command);

    expect(result.status, CameraApplyStatus.applied);
    expect(result.surfaceId, 'native-1');
    expect(result.actual!.center.latitude, closeTo(49.835, 1e-6));
    expect(result.actual!.center.longitude, closeTo(18.292, 1e-6));
    expect(result.actual!.zoom, 18);
    expect(native.moves, 1);
  });

  test('MapLibre waits for the native camera acknowledgement', () async {
    final native = _EventuallyConsistentMapLibreController();
    final viewport = MapLibreViewportController(native);
    const command = CameraCommand(
      surfaceId: 'native-1',
      destination: LatLng(49.835, 18.292),
      zoom: 18,
    );

    final resultFuture = viewport.applyCamera(command);
    await Future<void>.delayed(Duration.zero);
    viewport.notifyCameraChanged();
    final result = await resultFuture;

    expect(result.status, CameraApplyStatus.applied);
    expect(result.actual!.center.latitude, closeTo(49.835, 1e-6));
    expect(result.actual!.center.longitude, closeTo(18.292, 1e-6));
    expect(result.actual!.zoom, 18);
  });

  test('MapLibre replays focus after iOS ignores the cold first move',
      () async {
    final native = _ColdFirstMoveIgnoredMapLibreController();
    final viewport = MapLibreViewportController(native);
    const command = CameraCommand(
      surfaceId: 'native-1',
      destination: LatLng(49.835, 18.292),
      zoom: 18,
    );

    final resultFuture = viewport.applyCamera(command);
    await Future<void>.delayed(Duration.zero);
    viewport.notifyCameraChanged();
    final result =
        await resultFuture.timeout(const Duration(milliseconds: 100));

    expect(result.status, CameraApplyStatus.applied);
    expect(native.moves, 2);
  });
}

class _FakeMapLibreController implements ml.MapController {
  int moves = 0;
  ml.MapCamera _camera = const ml.MapCamera(
    center: ml.Geographic(lon: 18.2, lat: 49.8),
    zoom: 14,
    bearing: 0,
    pitch: 0,
  );

  @override
  ml.MapCamera getCamera() => _camera;

  @override
  Future<void> moveCamera({
    ml.Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    moves++;
    _camera = ml.MapCamera(
      center: center ?? _camera.center,
      zoom: zoom ?? _camera.zoom,
      bearing: bearing ?? _camera.bearing,
      pitch: pitch ?? _camera.pitch,
    );
  }

  @override
  Future<void> animateCamera({
    ml.Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    Duration nativeDuration = const Duration(seconds: 2),
    double webSpeed = 1.2,
    Duration? webMaxDuration,
    EdgeInsets padding = EdgeInsets.zero,
  }) =>
      moveCamera(
        center: center,
        zoom: zoom,
        bearing: bearing,
        pitch: pitch,
        padding: padding,
      );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _EventuallyConsistentMapLibreController
    extends _FakeMapLibreController {
  @override
  Future<void> moveCamera({
    ml.Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    moves++;
    final next = ml.MapCamera(
      center: center ?? _camera.center,
      zoom: zoom ?? _camera.zoom,
      bearing: bearing ?? _camera.bearing,
      pitch: pitch ?? _camera.pitch,
    );
    // The iOS native call completes before the camera event updates getCamera.
    // Model that platform ordering with the next event-loop turn.
    Future<void>.delayed(Duration.zero, () => _camera = next);
  }
}

final class _ColdFirstMoveIgnoredMapLibreController
    extends _FakeMapLibreController {
  @override
  Future<void> moveCamera({
    ml.Geographic? center,
    double? zoom,
    double? bearing,
    double? pitch,
    EdgeInsets padding = EdgeInsets.zero,
  }) async {
    moves++;
    if (moves == 1) return;
    _camera = ml.MapCamera(
      center: center ?? _camera.center,
      zoom: zoom ?? _camera.zoom,
      bearing: bearing ?? _camera.bearing,
      pitch: pitch ?? _camera.pitch,
    );
  }
}
