import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/map_renderer_host.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:latlong2/latlong.dart';

void main() {
  testWidgets('Legacy confirms first and warm second focus from actual camera',
      (tester) async {
    final viewport = MapViewportCoordinator();
    final model = MapSurfaceModel(
      active: true,
      scene: const MapScene(),
      icons: const [],
      initialCenter: const LatLng(49.8, 18.2),
      initialZoom: 14,
      viewport: viewport,
      onMapTap: (_) {},
      onPlaceTap: (_) {},
      onCameraReady: viewport.markReady,
    );
    await tester.pumpWidget(MaterialApp(
      home: SizedBox(
        width: 800,
        height: 600,
        child: MapRendererHost(
          renderer: OfflineMapRenderer.legacy,
          isOffline: true,
          model: model,
          legacy: LegacyMapConfiguration.offlineUnavailable(MapLayer()),
        ),
      ),
    ));
    await tester.pump();
    expect(viewport.isReady, isTrue);
    final surfaceId = viewport.surfaceId;

    const firstTarget = LatLng(49.835, 18.292);
    final first = await viewport.applyCamera(const CameraCommand(
      surfaceId: '',
      destination: firstTarget,
      zoom: 18,
    ).forSurface(surfaceId));
    expect(first.status, CameraApplyStatus.applied);
    expect(first.actual!.zoom, closeTo(18, 0.05));

    const secondTarget = LatLng(49.842, 18.281);
    final second = await viewport.applyCamera(const CameraCommand(
      surfaceId: '',
      destination: secondTarget,
      zoom: 18,
    ).forSurface(surfaceId));
    expect(second.status, CameraApplyStatus.applied);
    expect(
        second.actual!.center.latitude, closeTo(secondTarget.latitude, 1e-5));
    expect(viewport.surfaceId, surfaceId);
  });
}

extension on CameraCommand {
  CameraCommand forSurface(String id) => CameraCommand(
        surfaceId: id,
        destination: destination,
        zoom: zoom,
        centerToleranceMeters: centerToleranceMeters,
        zoomTolerance: zoomTolerance,
      );
}
