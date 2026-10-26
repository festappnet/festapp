import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:latlong2/latlong.dart';

/// Interaction zoom limits. Every renderer may safely zoom past its highest
/// native tile level; tile sources keep their own native cap and are overzoomed.
abstract final class MapZoomLimits {
  static const double interactionMaximum = 22;
  static const int onlineRasterNativeMaximum = 18;
}

/// Renderer-neutral input shared by both concrete map surface adapters.
final class MapSurfaceModel {
  /// Whether the owning navigation tab is currently visible.
  ///
  /// Native map views must not remain mounted behind an inactive tab: Android
  /// platform views may continue producing frames even while offstage.
  final bool active;

  final MapScene scene;
  final List<IconModel> icons;
  final LatLng initialCenter;
  final double initialZoom;
  final MapViewportCoordinator viewport;
  final ValueChanged<LatLng> onMapTap;
  final ValueChanged<int> onPlaceTap;
  final ValueChanged<int>? onPlaceLongPress;
  final VoidCallback? onCameraReady;
  final VoidCallback? onCameraChanged;
  final ValueChanged<double>? onZoomChanged;

  const MapSurfaceModel({
    required this.active,
    required this.scene,
    required this.icons,
    required this.initialCenter,
    required this.initialZoom,
    required this.viewport,
    required this.onMapTap,
    required this.onPlaceTap,
    this.onPlaceLongPress,
    this.onCameraReady,
    this.onCameraChanged,
    this.onZoomChanged,
  });
}
