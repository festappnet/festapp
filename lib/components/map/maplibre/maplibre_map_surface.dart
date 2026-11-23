import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/map/map_direction_marker.dart';
import 'package:fstapp/components/map/map_location_accuracy.dart';
import 'package:fstapp/components/map/map_location_pin_helper.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/maplibre/maplibre_scene_controller.dart';
import 'package:fstapp/components/map/maplibre/maplibre_place_icon_rasterizer.dart';
import 'package:fstapp/components/map/maplibre/maplibre_viewport_controller.dart';
import 'package:festapp_core/map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:fstapp/services/app_logger.dart';

class MapLibreMapSurface extends StatefulWidget {
  final String style;
  final MapSurfaceModel model;
  final VoidCallback? onStyleLoadTimeout;
  final VoidCallback? onStyleLoadSuccess;

  const MapLibreMapSurface({
    required this.style,
    required this.model,
    this.onStyleLoadTimeout,
    this.onStyleLoadSuccess,
    super.key,
  });

  @override
  State<MapLibreMapSurface> createState() => _MapLibreMapSurfaceState();
}

class _MapLibreMapSurfaceState extends State<MapLibreMapSurface> {
  ml.MapController? _controller;
  MapLibreViewportController? _viewportAdapter;
  MapLibreSceneController? _sceneController;
  final Map<String, int> _registeredIconVersions = {};
  final MapLibreStyleLoadWatchdog _styleLoadWatchdog =
      MapLibreStyleLoadWatchdog();
  bool _isStyleReady = false;
  Stream<ml.UserLocation>? _locations;

  @override
  void didUpdateWidget(covariant MapLibreMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _isStyleReady = false;
      _sceneController = null;
      _armStyleLoadWatchdog();
    }
    if (!widget.model.active || !widget.model.scene.showCurrentLocation) {
      _locations = null;
    }
    if (!identical(oldWidget.model.viewport, widget.model.viewport) &&
        _viewportAdapter != null) {
      oldWidget.model.viewport.detach(_viewportAdapter!);
      widget.model.viewport.attach(_viewportAdapter!);
    }
    if (oldWidget.model.scene != widget.model.scene ||
        oldWidget.model.icons != widget.model.icons) {
      _updateSceneAndIcons();
    }
  }

  @override
  void dispose() {
    _styleLoadWatchdog.dispose();
    final adapter = _viewportAdapter;
    if (adapter != null) {
      adapter.invalidate();
      widget.model.viewport.detach(adapter);
    }
    _controller = null;
    _viewportAdapter = null;
    _sceneController = null;
    _registeredIconVersions.clear();
    super.dispose();
  }

  void _onMapCreated(ml.MapController controller) {
    final oldAdapter = _viewportAdapter;
    if (oldAdapter != null) {
      oldAdapter.invalidate();
      widget.model.viewport.detach(oldAdapter);
    }
    _controller = controller;
    final adapter = MapLibreViewportController(controller);
    _viewportAdapter = adapter;
    widget.model.viewport.attach(adapter);
    _armStyleLoadWatchdog();
  }

  Future<void> _onStyleLoaded(ml.StyleController style) async {
    if (!mounted || !identical(_controller?.style, style)) return;
    _styleLoadWatchdog.cancel();
    widget.onStyleLoadSuccess?.call();
    await completeMapLibreStyleLoad(
      // The native style is already usable. Optional marker registration must
      // never leave the whole map hidden behind an infinite loading overlay.
      revealBaseMap: _revealBaseMap,
      decorateStyle: () async {
        _registeredIconVersions.clear();
        await _registerIcons(style);
        if (!mounted || !identical(_controller?.style, style)) return;
        final sceneController = MapLibreSceneController(style);
        _sceneController = sceneController;
        await sceneController.register(widget.model.scene);
      },
      onDecorationError: (error, stackTrace) => AppLogger.error(
        'MapLibre scene decoration failed: $error\n$stackTrace',
      ),
      markCameraReady: () {
        if (!mounted || !identical(_controller?.style, style)) return;
        widget.model.onZoomChanged?.call(_controller?.getCamera().zoom ?? 0);
        widget.model.onCameraReady?.call();
      },
    );
  }

  void _armStyleLoadWatchdog() {
    if (!mounted || _controller == null || _isStyleReady) return;
    _styleLoadWatchdog.arm(
      onTimeout: () {
        AppLogger.warning(
          'MapLibre style callback timed out; requesting offline bundle recovery.',
        );
        widget.onStyleLoadTimeout?.call();
      },
    );
  }

  void _revealBaseMap() {
    if (!mounted || _isStyleReady) return;
    setState(() => _isStyleReady = true);
  }

  Stream<ml.UserLocation> _trackLocation() async* {
    try {
      await for (final position in MapLocationAccuracy.positionStream()) {
        yield ml.UserLocation(
          position: ml.Geographic(
            lon: position.longitude,
            lat: position.latitude,
          ),
          accuracy: position.accuracy > 0 ? position.accuracy : null,
          timestamp: position.timestamp,
        );
      }
    } catch (error, stackTrace) {
      AppLogger.warning(
        'MapLibre location tracking failed: $error\n$stackTrace',
      );
    }
  }

  Future<void> _registerIcons(ml.StyleController style) async {
    if (!mounted || !identical(_controller?.style, style)) return;
    final iconsToRegister = <String, _MapImageRegistration>{};
    for (final place in widget.model.scene.places) {
      final color = Color(place.pinColorValue);
      final svg = MapLocationPinHelper.resolveIconData(
        place.place,
        widget.model.icons,
      );
      final registration = _MapImageRegistration(
        widget: Icon(
          Icons.location_pin,
          size: MapLibreSceneController.fallbackPlaceIconSize,
          color: color,
        ),
        size: const Size(58, 52),
        svg: svg,
        pinColor: color,
        rasterScale: _imageRasterScale,
        version: Object.hash(svg, color, _imageRasterScale),
      );
      if (_registeredIconVersions[place.iconKey] == registration.version) {
        continue;
      }
      iconsToRegister[place.iconKey] = registration;
    }
    for (final direction in widget.model.scene.directions) {
      final registration = _MapImageRegistration(
        widget: MapDirectionMarker(
          color: Color(direction.colorValue),
          bodyPixels: direction.bodyPixels,
        ),
        size: MapDirectionMarker.sizeFor(direction.bodyPixels),
        rasterScale: _imageRasterScale,
        version: Object.hash(
          direction.colorValue,
          direction.bodyPixels,
          _imageRasterScale,
        ),
      );
      if (_registeredIconVersions[direction.iconKey] == registration.version) {
        continue;
      }
      iconsToRegister[direction.iconKey] = registration;
    }
    final rasterCache = <String, ui.Image>{};
    try {
      for (final icon in iconsToRegister.entries) {
        if (!mounted || !identical(_controller?.style, style)) return;
        final registration = icon.value;
        final svg = registration.svg;
        if (svg != null && registration.pinColor != null) {
          try {
            final cacheKey = '${registration.rasterScale}\u0000$svg';
            final raster = rasterCache[cacheKey] ??=
                await MapLibrePlaceIconRasterizer.rasterize(
                  svg,
                  pixelRatio: registration.rasterScale,
                );
            if (!mounted || !identical(_controller?.style, style)) return;
            await style.addImageFromWidget(
              id: icon.key,
              widget: MapLocationPinHelper.rasterIcon(
                context,
                raster,
                pinColor: registration.pinColor!,
              ),
              logicalSize: registration.size,
              imageSize: registration.size * registration.rasterScale,
            );
          } catch (error) {
            AppLogger.error(
              'MapLibre SVG pin rasterization failed for ${icon.key}: $error',
            );
            await _addWidgetImage(style, icon.key, registration);
          }
        } else {
          await _addWidgetImage(style, icon.key, registration);
        }
        _registeredIconVersions[icon.key] = registration.version;
      }
    } finally {
      for (final raster in rasterCache.values) {
        raster.dispose();
      }
    }
  }

  Future<void> _addWidgetImage(
    ml.StyleController style,
    String id,
    _MapImageRegistration registration,
  ) => style.addImageFromWidget(
    id: id,
    widget: registration.widget,
    logicalSize: registration.size,
    imageSize: registration.size * registration.rasterScale,
  );

  double get _imageRasterScale => MediaQuery.devicePixelRatioOf(context);

  Future<void> _updateSceneAndIcons() async {
    final style = _controller?.style;
    final sceneController = _sceneController;
    if (style == null || sceneController == null) return;
    await _registerIcons(style);
    await sceneController.update(widget.model.scene);
  }

  void _onCameraChanged() {
    _viewportAdapter?.notifyCameraChanged();
    widget.model.onCameraChanged?.call();
  }

  Future<void> _onMapInput(ml.MapEventUserInput event) async {
    final controller = _controller;
    if (controller == null || !widget.model.active) return;
    final features = await controller.queryRenderedFeatures(
      ml.QueryGeometry.point(event.screenPoint),
      layerIds: const [MapLibreSceneController.placeLayerId],
    );
    if (!mounted ||
        !identical(_controller, controller) ||
        !widget.model.active) {
      return;
    }
    if (features.isNotEmpty) {
      final rawId = features.first.properties['place_id'];
      final placeId = rawId is num ? rawId.toInt() : int.tryParse('$rawId');
      if (placeId != null) {
        if (event is ml.MapEventLongClick) {
          widget.model.onPlaceLongPress?.call(placeId);
        } else {
          widget.model.onPlaceTap(placeId);
        }
        return;
      }
    }
    if (event is ml.MapEventClick) {
      widget.model.onMapTap(LatLng(event.point.lat, event.point.lon));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        ml.MapLibreMap(
          paused: !widget.model.active,
          options: ml.MapOptions(
            style: ml.MapStyle.json(widget.style),
            initCamera: ml.CameraUpdate.position(
              center: ml.Geographic(
                lon: widget.model.initialCenter.longitude,
                lat: widget.model.initialCenter.latitude,
              ),
              zoom: widget.model.initialZoom,
            ),
            minZoom: 0,
            maxZoom: MapZoomLimits.interactionMaximum,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onCameraMove: (_) => _onCameraChanged(),
          onCameraMoveEnd: (event) {
            _onCameraChanged();
            widget.model.onZoomChanged?.call(event.camera.zoom);
          },
          onClick: _onMapInput,
          onLongClick: _onMapInput,
          children: [
            if (widget.model.active && widget.model.scene.showCurrentLocation)
              ml.UserLocationLayer(
                locations: _locations ??= _trackLocation(),
                style: const ml.UserLocationStyle(showHeading: false),
              ),
          ],
        ),
        IgnorePointer(
          child: AnimatedOpacity(
            opacity: _isStyleReady ? 0 : 1,
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colors.surfaceContainer, colors.surface],
                ),
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.map_outlined, size: 42, color: colors.primary),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      MapStrings.loadingMap,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MapImageRegistration {
  final Widget widget;
  final Size size;
  final String? svg;
  final Color? pinColor;
  final double rasterScale;
  final int version;

  const _MapImageRegistration({
    required this.widget,
    required this.size,
    this.svg,
    this.pinColor,
    this.rasterScale = 1,
    required this.version,
  });
}
