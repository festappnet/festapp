import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_animations/flutter_map_animations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/map_feature.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/map_direction_marker.dart';
import 'package:fstapp/components/map/map_location_pin_helper.dart';
import 'package:fstapp/components/map/map_location_style.dart';
import 'package:fstapp/components/map/map_scene.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/map_viewport_controller.dart';
import 'package:fstapp/components/map/legacy_map_resources.dart';
import 'package:latlong2/latlong.dart';
import 'package:fstapp/services/launch_url_service.dart';

export 'package:fstapp/components/map/legacy_map_resources.dart';

/// All flutter_map knowledge is localized in this adapter. It consumes the
/// same immutable [MapSurfaceModel] as the MapLibre adapter.
class LegacyMapSurface extends StatefulWidget {
  final bool offline;
  final MapLayer layer;
  final MapSurfaceModel model;
  final LegacyMapResources? offlineResources;
  final String? offlineSourceName;

  const LegacyMapSurface({
    required this.offline,
    required this.layer,
    required this.model,
    this.offlineResources,
    this.offlineSourceName,
    super.key,
  });

  @override
  State<LegacyMapSurface> createState() => _LegacyMapSurfaceState();
}

class _LegacyMapSurfaceState extends State<LegacyMapSurface>
    with TickerProviderStateMixin {
  static const _openStreetMapTiles =
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const _tileUserAgent = 'Festapp/Flutter (+${AppConfig.supportUrl})';
  late final AnimatedMapController _animatedController =
      AnimatedMapController(vsync: this);
  late final LegacyMapViewportController _viewportAdapter =
      LegacyMapViewportController(_animatedController);
  bool _usingOpenStreetMapFallback = false;

  @override
  void initState() {
    super.initState();
    widget.model.viewport.attach(_viewportAdapter);
  }

  @override
  void didUpdateWidget(covariant LegacyMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.offline != widget.offline ||
        oldWidget.layer.layerLink != widget.layer.layerLink) {
      _usingOpenStreetMapFallback = false;
    }
    if (!identical(oldWidget.model.viewport, widget.model.viewport)) {
      oldWidget.model.viewport.detach(_viewportAdapter);
      widget.model.viewport.attach(_viewportAdapter);
    }
  }

  @override
  void dispose() {
    widget.model.viewport.detach(_viewportAdapter);
    _animatedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseLayers = widget.offline
        ? <Widget>[_buildOfflineBaseLayer()]
        : _buildOnlineBaseLayers();
    return fm.FlutterMap(
      mapController: _animatedController.mapController,
      options: fm.MapOptions(
        interactionOptions: const fm.InteractionOptions(
          flags: fm.InteractiveFlag.doubleTapDragZoom |
              fm.InteractiveFlag.doubleTapZoom |
              fm.InteractiveFlag.pinchMove |
              fm.InteractiveFlag.pinchZoom |
              fm.InteractiveFlag.flingAnimation |
              fm.InteractiveFlag.drag |
              fm.InteractiveFlag.scrollWheelZoom,
        ),
        initialZoom: widget.model.initialZoom,
        maxZoom: MapZoomLimits.interactionMaximum,
        initialCenter: widget.model.initialCenter,
        onTap: (_, location) => widget.model.onMapTap(location),
        onMapReady: () {
          widget.model.onZoomChanged
              ?.call(_animatedController.mapController.camera.zoom - 1);
          widget.model.onCameraReady?.call();
        },
        onPositionChanged: (camera, _) {
          widget.model.onCameraChanged?.call();
          widget.model.onZoomChanged?.call(camera.zoom - 1);
        },
      ),
      children: [
        ...baseLayers,
        _buildAttribution(),
        _buildPathLayer(widget.model.scene.paths),
        _buildDirectionLayer(widget.model.scene.directions),
        if (widget.model.scene.showCurrentLocation &&
            widget.model.scene.currentLocation != null)
          fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: widget.model.scene.currentLocation!,
                width: MapLocationStyle.onMapMarkerSize,
                height: MapLocationStyle.onMapMarkerSize,
                child: const _CurrentLocationMarker(
                  key: Key('legacy-current-location-marker'),
                ),
              ),
            ],
          ),
        fm.MarkerLayer(markers: _buildMarkers()),
      ],
    );
  }

  List<Widget> _buildOnlineBaseLayers() {
    final configured = widget.layer.layerLink?.trim();
    final configuredPrimary = configured == null || configured.isEmpty
        ? _openStreetMapTiles
        : configured;
    final primary =
        _usingOpenStreetMapFallback ? _openStreetMapTiles : configuredPrimary;

    fm.TileLayer tiles(String url) => fm.TileLayer(
          key: ValueKey(url),
          tileProvider: fm.NetworkTileProvider(
            headers: {'User-Agent': _tileUserAgent},
            // Providers such as Mapy.com return a branded PNG together with
            // HTTP 403. Treat the status as an error so flutter_map requests
            // the configured OpenStreetMap fallback instead of rendering it.
            attemptDecodeOfHttpErrorResponses: false,
          ),
          maxZoom: MapZoomLimits.interactionMaximum,
          maxNativeZoom: MapZoomLimits.onlineRasterNativeMaximum,
          urlTemplate: url,
          errorTileCallback: primary == _openStreetMapTiles
              ? null
              : (_, __, ___) => _activateOpenStreetMapFallback(),
        );

    return [tiles(primary)];
  }

  void _activateOpenStreetMapFallback() {
    if (_usingOpenStreetMapFallback || !mounted) return;
    setState(() => _usingOpenStreetMapFallback = true);
  }

  Widget _buildOfflineBaseLayer() {
    final resources = widget.offlineResources;
    final sourceName = widget.offlineSourceName;
    if (resources == null || sourceName == null) {
      return const SizedBox.shrink();
    }
    return resources.buildBaseLayer(
      sourceName: sourceName,
      maximumZoom: MapZoomLimits.interactionMaximum,
    );
  }

  Widget _buildAttribution() {
    if (widget.offline) {
      final text = widget.layer.text;
      if (text == null || text.isEmpty) return const SizedBox.shrink();
      return fm.RichAttributionWidget(
        showFlutterMapAttribution: false,
        animationConfig: const fm.ScaleRAWA(),
        attributions: [fm.TextSourceAttribution(text)],
      );
    }
    final configured = widget.layer.layerLink?.trim();
    final usesOpenStreetMap = _usingOpenStreetMapFallback ||
        configured == null ||
        configured.isEmpty ||
        configured == _openStreetMapTiles;
    if (usesOpenStreetMap) {
      return fm.RichAttributionWidget(
        showFlutterMapAttribution: false,
        animationConfig: const fm.ScaleRAWA(),
        attributions: const [
          fm.TextSourceAttribution(MapStrings.openStreetMapAttribution),
        ],
      );
    }
    if ((widget.layer.logo?.isNotEmpty ?? false) ||
        (widget.layer.text?.isNotEmpty ?? false)) {
      return fm.RichAttributionWidget(
        showFlutterMapAttribution: false,
        animationConfig: const fm.ScaleRAWA(),
        attributions: [
          if (widget.layer.logo?.isNotEmpty ?? false)
            fm.LogoSourceAttribution(
              SvgPicture.network(widget.layer.logo!, height: 28),
              onTap: widget.layer.logoLink?.isNotEmpty ?? false
                  ? () => LaunchUrlService.openExternalUrl(
                        widget.layer.logoLink!,
                      )
                  : null,
            ),
          if (widget.layer.text?.isNotEmpty ?? false)
            fm.TextSourceAttribution(
              widget.layer.text!,
              onTap: widget.layer.textLink?.isNotEmpty ?? false
                  ? () => LaunchUrlService.openExternalUrl(
                        widget.layer.textLink!,
                      )
                  : null,
            ),
        ],
      );
    }
    return const SizedBox.shrink();
  }

  List<fm.Marker> _buildMarkers() {
    return [
      ...widget.model.scene.places.map((presentation) => fm.Marker(
            point: presentation.coordinate,
            width: 58,
            height: 52,
            alignment: Alignment.topCenter,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => widget.model.onPlaceTap(presentation.placeId),
              onLongPress: widget.model.onPlaceLongPress == null
                  ? null
                  : () => widget.model.onPlaceLongPress!(presentation.placeId),
              child: _LegacyPlaceMarker(
                presentation: presentation,
                icons: widget.model.icons,
              ),
            ),
          )),
      ...widget.model.scene.drawPoints.map((point) => fm.Marker(
            point: point.coordinate,
            width: 22,
            height: 22,
            alignment: Alignment.center,
            child: Icon(
              Icons.circle,
              size: 14,
              color: Color(point.colorValue),
            ),
          )),
    ];
  }

  static Widget _buildPathLayer(List<MapPathPresentation> paths) {
    return fm.PolylineLayer(
      polylines: paths
          .map((path) => fm.Polyline(
                points: path.points,
                color: Color(path.colorValue),
                strokeWidth: path.strokeWidth,
              ))
          .toList(growable: false),
    );
  }

  static Widget _buildDirectionLayer(
    List<MapDirectionPresentation> directions,
  ) {
    return fm.MarkerLayer(
      markers: directions.map((direction) {
        final size = MapDirectionMarker.sizeFor(direction.bodyPixels);
        return fm.Marker(
          point: direction.coordinate,
          width: size.width,
          height: size.height,
          alignment: Alignment.center,
          child: Transform.rotate(
            angle: direction.bearingDegrees * pi / 180,
            child: MapDirectionMarker(
              color: Color(direction.colorValue),
              bodyPixels: direction.bodyPixels,
            ),
          ),
        );
      }).toList(growable: false),
    );
  }
}

class _CurrentLocationMarker extends StatelessWidget {
  const _CurrentLocationMarker({super.key});

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: const Padding(
          padding: EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: MapLocationStyle.color,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

class _LegacyPlaceMarker extends StatelessWidget {
  final MapPlacePresentation presentation;
  final List<IconModel> icons;

  const _LegacyPlaceMarker({
    required this.presentation,
    required this.icons,
  });

  @override
  Widget build(BuildContext context) {
    final pinColor = Color(presentation.pinColorValue);
    final icon = MapLocationPinHelper.type2icon(
      context,
      presentation.place,
      icons,
      pinColor: pinColor,
    );
    if (!presentation.showTitle) {
      return icon ?? Icon(Icons.location_pin, size: 36, color: pinColor);
    }
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        icon ?? Icon(Icons.location_pin, size: 36, color: pinColor),
        Positioned(
          top: 0,
          left: 36,
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                presentation.title,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LegacyMapViewportController implements MapViewportController {
  final AnimatedMapController controller;

  LegacyMapViewportController(this.controller);

  @override
  MapCameraState get camera => MapCameraState(
        center: controller.mapController.camera.center,
        zoom: controller.mapController.camera.zoom,
      );

  @override
  double get directionLayoutZoom => controller.mapController.camera.zoom - 1;

  @override
  Future<CameraApplyResult> applyCamera(CameraCommand command) async {
    // A retained map can be put under TickerMode while an earlier camera
    // animation is still pending. If that animation resumes after navigation,
    // it would overwrite this required destination. Navigation state wins over
    // cosmetic motion, so cancel every pending animation before applying this
    // required transition.
    controller.stopAnimations();
    if (command.transition == CameraTransition.animated) {
      await controller.animateTo(
        dest: command.destination,
        zoom: command.zoom + 1,
      );
    } else {
      controller.mapController.move(
        command.destination,
        command.zoom + 1,
      );
    }
    final raw = controller.mapController.camera;
    final actual = MapCameraState(center: raw.center, zoom: raw.zoom - 1);
    final centerMatches = const Distance().as(
          LengthUnit.Meter,
          actual.center,
          command.destination,
        ) <=
        command.centerToleranceMeters;
    final zoomMatches =
        (actual.zoom - command.zoom).abs() <= command.zoomTolerance;
    return CameraApplyResult(
      status: centerMatches && zoomMatches
          ? CameraApplyStatus.applied
          : CameraApplyStatus.retryable,
      surfaceId: command.surfaceId,
      command: command,
      actual: actual,
      reason: centerMatches && zoomMatches ? null : 'actualCameraMismatch',
    );
  }

  @override
  Future<void> animateTo(
    LatLng destination, {
    double? zoom,
    Curve curve = Curves.easeInOut,
    Duration? duration,
  }) =>
      controller.animateTo(
        dest: destination,
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
      controller.animatedFitCamera(
        cameraFit: fm.CameraFit.coordinates(
          coordinates: coordinates,
          padding: padding,
        ),
        curve: curve,
      );

  @override
  Offset coordinateToScreenPoint(LatLng coordinate) =>
      controller.mapController.camera.latLngToScreenOffset(coordinate);

  @override
  LatLng screenPointToCoordinate(Offset point) =>
      controller.mapController.camera.screenOffsetToLatLng(point);
}
