import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:fstapp/components/map/map_direction_marker.dart';
import 'package:fstapp/components/map/map_location_accuracy.dart';
import 'package:fstapp/components/map/map_location_pin_helper.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/map_surface_model.dart';
import 'package:fstapp/components/map/maplibre/maplibre_scene_controller.dart';
import 'package:fstapp/components/map/maplibre/maplibre_place_icon_rasterizer.dart';
import 'package:fstapp/components/map/maplibre/maplibre_viewport_controller.dart';
import 'package:fstapp/components/map/maplibre/maplibre_style_load_guard.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre/maplibre.dart' as ml;
import 'package:fstapp/services/app_logger.dart';

class MapLibreMapSurface extends StatefulWidget {
  final String style;
  final MapSurfaceModel model;

  const MapLibreMapSurface({
    required this.style,
    required this.model,
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
  bool _isStyleReady = false;

  @override
  void didUpdateWidget(covariant MapLibreMapSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      _isStyleReady = false;
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
  }

  Future<void> _onStyleLoaded(ml.StyleController style) async {
    if (!mounted || !identical(_controller?.style, style)) return;
    await completeMapLibreStyleLoad(
      // The native style is already usable. Optional marker registration must
      // never leave the whole map hidden behind an infinite loading overlay.
      revealBaseMap: () => setState(() => _isStyleReady = true),
      decorateStyle: () async {
        _registeredIconVersions.clear();
        await _registerIcons(style);
        if (!mounted || !identical(_controller?.style, style)) return;
        final sceneController = MapLibreSceneController(style);
        _sceneController = sceneController;
        await sceneController.register(widget.model.scene);
        await _enableLocationIfAllowed();
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

  Future<void> _enableLocationIfAllowed() async {
    final controller = _controller;
    if (!widget.model.scene.showCurrentLocation ||
        controller == null ||
        !ml.MapController.userLocationIsSupported) {
      return;
    }
    if (await MapLocationAccuracy.ensurePermission()) {
      // A continuously pulsing/animating puck requests frames even while the
      // map itself is idle. A static location + accuracy indicator preserves
      // the useful information without turning an idle map into a 60 FPS view.
      await controller.enableLocation(
        pulse: false,
        pulseFade: false,
        accuracyAnimation: false,
        compassAnimation: false,
        bearingRenderMode: ml.BearingRenderMode.none,
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
  ) =>
      style.addImageFromWidget(
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

  void _onEvent(ml.MapEvent event) {
    if (event is ml.MapEventMoveCamera || event is ml.MapEventCameraIdle) {
      _viewportAdapter?.notifyCameraChanged();
      widget.model.onCameraChanged?.call();
    }
    final controller = _controller;
    if (event is ml.MapEventCameraIdle && controller != null) {
      widget.model.onZoomChanged?.call(controller.getCamera().zoom);
    }
    if (event is! ml.MapEventUserInput || controller == null) {
      return;
    }
    if (event is! ml.MapEventClick && event is! ml.MapEventLongClick) {
      return;
    }
    final features = controller.featuresAtPoint(
      event.screenPoint,
      layerIds: const [MapLibreSceneController.placeLayerId],
    );
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
          active: widget.model.active,
          options: ml.MapOptions(
            initStyle: widget.style,
            initCenter: ml.Geographic(
              lon: widget.model.initialCenter.longitude,
              lat: widget.model.initialCenter.latitude,
            ),
            initZoom: widget.model.initialZoom,
            minZoom: 0,
            maxZoom: MapZoomLimits.interactionMaximum,
            // The feasibility benchmark selected Hybrid Composition without the
            // expensive texture mode. Keep this explicit; never inherit defaults.
            androidTextureMode: false,
            androidMode: ml.AndroidPlatformViewMode.hc,
          ),
          onMapCreated: _onMapCreated,
          onStyleLoaded: _onStyleLoaded,
          onEvent: _onEvent,
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
                    Icon(
                      Icons.map_outlined,
                      size: 42,
                      color: colors.primary,
                    ),
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
