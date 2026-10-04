import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/services/app_logger.dart';

import 'feature.dart';
import 'feature_constants.dart';

/// Feature for maps with separate online and offline map layers.
class MapFeature extends Feature {
  static const MapLocation defaultLocation =
      MapLocation(lat: 49.1038023, lng: 17.3947819);
  MapLayer onlineMapLayer;
  MapLayer offlineMapLayer;
  double defaultMapZoom;
  MapLocation defaultMapLocation;

  MapFeature({
    super.code = FeatureConstants.map,
    super.isEnabled,
    super.title,
    super.description,
    MapLayer? onlineMapLayer,
    MapLayer? offlineMapLayer,
    this.defaultMapZoom = 17.0,
    this.defaultMapLocation = defaultLocation,
  })  : onlineMapLayer = onlineMapLayer ?? MapLayer(),
        offlineMapLayer = offlineMapLayer ?? MapLayer();

  factory MapFeature.getDefault() {
    return MapFeature(
      onlineMapLayer: MapLayer(),
      offlineMapLayer: MapLayer(),
    );
  }

  factory MapFeature.fromJson(Map<String, dynamic> json) {
    return MapFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      onlineMapLayer: json[FeatureConstants.onlineMapLayer] != null
          ? MapLayer.fromJson(json[FeatureConstants.onlineMapLayer])
          : MapLayer(),
      offlineMapLayer: json[FeatureConstants.offlineMapLayer] != null
          ? MapLayer.fromJson(json[FeatureConstants.offlineMapLayer])
          : MapLayer(),
      defaultMapZoom:
          (json[FeatureConstants.defaultMapZoom]?.toDouble() ?? 17.0),
      defaultMapLocation: json[FeatureConstants.defaultMapLocation] != null
          ? MapLocation.fromJson(json[FeatureConstants.defaultMapLocation])
          : defaultLocation,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.defaultMapZoom: defaultMapZoom,
      FeatureConstants.defaultMapLocation: defaultMapLocation,
      FeatureConstants.onlineMapLayer: onlineMapLayer.toJson(),
      FeatureConstants.offlineMapLayer: offlineMapLayer.toJson(),
    };
  }

  /// Builds the form field for this feature in FeatureForm.
  @override
  Widget buildFormField(BuildContext context) {
    return StatefulBuilder(
      builder: (ctx, updateLocal) {
        void setLocalState(VoidCallback change) {
          updateLocal(change);
          EditorDraftScope.changed(ctx);
        }

        // controllers local to this builder
        final zoomCtrl = TextEditingController(text: defaultMapZoom.toString());
        final latCtrl =
            TextEditingController(text: defaultMapLocation.lat.toString());
        final lngCtrl =
            TextEditingController(text: defaultMapLocation.lng.toString());

        final onlineLogo = TextEditingController(text: onlineMapLayer.logo);
        final onlineText = TextEditingController(text: onlineMapLayer.text);
        final onlineLogoLink =
            TextEditingController(text: onlineMapLayer.logoLink);
        final onlineTextLink =
            TextEditingController(text: onlineMapLayer.textLink);
        final onlineLayerLink =
            TextEditingController(text: onlineMapLayer.layerLink);

        final offlineLogo = TextEditingController(text: offlineMapLayer.logo);
        final offlineText = TextEditingController(text: offlineMapLayer.text);
        final offlineLogoLink =
            TextEditingController(text: offlineMapLayer.logoLink);
        final offlineTextLink =
            TextEditingController(text: offlineMapLayer.textLink);

        MapBaseMode mapBaseMode = offlineMapLayer.mapBaseMode;
        final pkgCtrl =
            TextEditingController(text: offlineMapLayer.offlineMapPackageURL);
        final styleCtrl =
            TextEditingController(text: offlineMapLayer.offlineMapStyleURL);
        final layerNameCtrl =
            TextEditingController(text: offlineMapLayer.offlineMapLayerName);
        final manifestCtrl = TextEditingController(
          text: offlineMapLayer.offlineMapBundleManifestURL,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // zoom
            TextFormField(
              controller: zoomCtrl,
              decoration: InputDecoration(labelText: FeaturesStrings.mapZoom),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onSaved: (val) =>
                  defaultMapZoom = double.tryParse(val ?? '') ?? defaultMapZoom,
            ),

            const SizedBox(height: 16),
            // lat / lng
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: latCtrl,
                  decoration:
                      InputDecoration(labelText: FeaturesStrings.latitude),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onSaved: (val) {
                    final lat =
                        double.tryParse(val ?? '') ?? defaultMapLocation.lat;
                    defaultMapLocation =
                        MapLocation(lat: lat, lng: defaultMapLocation.lng);
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: TextFormField(
                  controller: lngCtrl,
                  decoration:
                      InputDecoration(labelText: FeaturesStrings.longitude),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  onSaved: (val) {
                    final lng =
                        double.tryParse(val ?? '') ?? defaultMapLocation.lng;
                    defaultMapLocation =
                        MapLocation(lat: defaultMapLocation.lat, lng: lng);
                  },
                ),
              ),
            ]),

            const SizedBox(height: 16),
            ExpansionTile(
              title: Text(FeaturesStrings.mapLayerSettings),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: onlineLogo,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerLogo),
                        onSaved: (val) => onlineMapLayer.logo = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: onlineText,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerText),
                        onSaved: (val) => onlineMapLayer.text = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: onlineLogoLink,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerLogoLink),
                        onSaved: (val) => onlineMapLayer.logoLink = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: onlineTextLink,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerTextLink),
                        onSaved: (val) => onlineMapLayer.textLink = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: onlineLayerLink,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerUrl),
                        onSaved: (val) => onlineMapLayer.layerLink = val ?? '',
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            ExpansionTile(
              title: Text(FeaturesStrings.offlineMapLayerSettings),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: offlineLogo,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerLogo),
                        onSaved: (val) => offlineMapLayer.logo = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: offlineText,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerText),
                        onSaved: (val) => offlineMapLayer.text = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: offlineLogoLink,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerLogoLink),
                        onSaved: (val) => offlineMapLayer.logoLink = val ?? '',
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: offlineTextLink,
                        decoration: InputDecoration(
                            labelText: FeaturesStrings.mapLayerTextLink),
                        onSaved: (val) => offlineMapLayer.textLink = val ?? '',
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<MapBaseMode>(
                        initialValue: mapBaseMode,
                        decoration: InputDecoration(
                          labelText: FeaturesStrings.mapBaseMode,
                          helperText: FeaturesStrings.mapBaseModeDescription,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: MapBaseMode.online,
                            child: Text(FeaturesStrings.mapBaseModeOnline),
                          ),
                          DropdownMenuItem(
                            value: MapBaseMode.legacy,
                            child: Text(FeaturesStrings.mapBaseModeLegacy),
                          ),
                          DropdownMenuItem(
                            value: MapBaseMode.maplibre,
                            child: Text(FeaturesStrings.mapBaseModeMapLibre),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setLocalState(() {
                            mapBaseMode = value;
                            offlineMapLayer.mapBaseMode = value;
                          });
                        },
                      ),
                      if (mapBaseMode == MapBaseMode.maplibre) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: manifestCtrl,
                          decoration: InputDecoration(
                            labelText:
                                FeaturesStrings.offlineMapBundleManifestUrl,
                          ),
                          validator: (value) => _validateRequiredHttpsUrl(
                            value,
                            FeaturesStrings.mapLibreBundleManifestRequired,
                          ),
                          onSaved: (val) => offlineMapLayer
                              .offlineMapBundleManifestURL = val ?? '',
                        ),
                      ] else if (mapBaseMode == MapBaseMode.legacy) ...[
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: pkgCtrl,
                          decoration: InputDecoration(
                              labelText: FeaturesStrings.offlineMapPackageUrl),
                          validator: (value) => _validateRequiredHttpsUrl(
                            value,
                            FeaturesStrings.offlineMapRendererFieldRequired,
                          ),
                          onSaved: (val) =>
                              offlineMapLayer.offlineMapPackageURL = val ?? '',
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: styleCtrl,
                          decoration: InputDecoration(
                              labelText: FeaturesStrings.offlineMapStyleUrl),
                          validator: (value) => _validateRequiredHttpsUrl(
                            value,
                            FeaturesStrings.offlineMapRendererFieldRequired,
                          ),
                          onSaved: (val) =>
                              offlineMapLayer.offlineMapStyleURL = val ?? '',
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: layerNameCtrl,
                          decoration: InputDecoration(
                              labelText: FeaturesStrings.offlineMapLayerName),
                          validator: (value) => value == null ||
                                  value.trim().isEmpty
                              ? FeaturesStrings.offlineMapRendererFieldRequired
                              : null,
                          onSaved: (val) =>
                              offlineMapLayer.offlineMapLayerName = val ?? '',
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

String? _validateRequiredHttpsUrl(String? value, String requiredMessage) {
  final normalized = value?.trim() ?? '';
  if (normalized.isEmpty) return requiredMessage;

  final uri = Uri.tryParse(normalized);
  if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) {
    return FeaturesStrings.offlineMapHttpsUrlRequired;
  }
  return null;
}

/// Helper class representing a map location.
class MapLocation {
  final double lat;
  final double lng;

  const MapLocation({
    required this.lat,
    required this.lng,
  });

  factory MapLocation.fromJson(Map<String, dynamic> json) {
    return MapLocation(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lat': lat,
      'lng': lng,
    };
  }
}

enum OfflineMapRenderer {
  maplibre('maplibre'),
  legacy('legacy');

  final String wireValue;

  const OfflineMapRenderer(this.wireValue);

  static OfflineMapRenderer parse(Object? value) {
    if (value == null) return OfflineMapRenderer.maplibre;
    for (final renderer in OfflineMapRenderer.values) {
      if (renderer.wireValue == value) return renderer;
    }
    AppLogger.error('Invalid offlineMapRenderer configuration: $value');
    throw FormatException('Unknown offline map renderer: $value');
  }
}

/// The occasion-wide base map shown by native clients.
///
/// This is the settings-facing interface. It deliberately maps onto the
/// existing wire-compatible `forceOfflineMap` + `offlineMapRenderer` fields so
/// older clients and the configured offline fallback keep working.
enum MapBaseMode { online, legacy, maplibre }

/// Helper class representing a map layer.
class MapLayer {
  String? logo;
  String? text;
  String? logoLink;
  String? textLink;
  String? layerLink;
  // Offline extra fields (for offline map layer)
  String? offlineMapPackageURL;
  String? offlineMapStyleURL;
  String? offlineMapLayerName;
  OfflineMapRenderer offlineMapRenderer;
  bool hasExplicitOfflineMapRenderer;
  String? offlineMapBundleManifestURL;
  bool forceOfflineMap;

  MapLayer({
    this.logo,
    this.text,
    this.logoLink,
    this.textLink,
    this.layerLink = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    this.offlineMapPackageURL,
    this.offlineMapStyleURL,
    this.offlineMapLayerName,
    OfflineMapRenderer? offlineMapRenderer,
    bool? hasExplicitOfflineMapRenderer,
    this.offlineMapBundleManifestURL,
    this.forceOfflineMap = false,
  })  : offlineMapRenderer = offlineMapRenderer ?? OfflineMapRenderer.maplibre,
        hasExplicitOfflineMapRenderer =
            hasExplicitOfflineMapRenderer ?? offlineMapRenderer != null;

  MapBaseMode get mapBaseMode {
    if (!forceOfflineMap) return MapBaseMode.online;
    return switch (offlineMapRenderer) {
      OfflineMapRenderer.legacy => MapBaseMode.legacy,
      OfflineMapRenderer.maplibre => MapBaseMode.maplibre,
    };
  }

  set mapBaseMode(MapBaseMode mode) {
    switch (mode) {
      case MapBaseMode.online:
        forceOfflineMap = false;
        break;
      case MapBaseMode.legacy:
        forceOfflineMap = true;
        offlineMapRenderer = OfflineMapRenderer.legacy;
        hasExplicitOfflineMapRenderer = true;
        break;
      case MapBaseMode.maplibre:
        forceOfflineMap = true;
        offlineMapRenderer = OfflineMapRenderer.maplibre;
        hasExplicitOfflineMapRenderer = true;
        break;
    }
  }

  factory MapLayer.fromJson(Map<String, dynamic> json) {
    final hasExplicitRenderer =
        json.containsKey(FeatureConstants.offlineMapRenderer);
    final hasLegacyContract =
        _hasText(json[FeatureConstants.offlineMapPackageURL]) &&
            _hasText(json[FeatureConstants.offlineMapStyleURL]) &&
            _hasText(json[FeatureConstants.offlineMapLayerName]);
    final renderer = hasExplicitRenderer
        ? OfflineMapRenderer.parse(json[FeatureConstants.offlineMapRenderer])
        : hasLegacyContract
            ? OfflineMapRenderer.legacy
            : OfflineMapRenderer.maplibre;
    return MapLayer(
      logo: json[FeatureConstants.mapLogo] as String?,
      text: json[FeatureConstants.mapText] as String?,
      logoLink: json[FeatureConstants.mapLogoLink] as String?,
      textLink: json[FeatureConstants.mapTextLink] as String?,
      layerLink: json[FeatureConstants.mapLayerLink] as String? ??
          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      offlineMapPackageURL:
          json[FeatureConstants.offlineMapPackageURL] as String?,
      offlineMapStyleURL: json[FeatureConstants.offlineMapStyleURL] as String?,
      offlineMapLayerName:
          json[FeatureConstants.offlineMapLayerName] as String?,
      offlineMapRenderer: renderer,
      hasExplicitOfflineMapRenderer: hasExplicitRenderer,
      offlineMapBundleManifestURL:
          json[FeatureConstants.offlineMapBundleManifestURL] as String?,
      forceOfflineMap: json[FeatureConstants.forceOfflineMap] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    final data = {
      FeatureConstants.mapLogo: logo,
      FeatureConstants.mapText: text,
      FeatureConstants.mapLogoLink: logoLink,
      FeatureConstants.mapTextLink: textLink,
      FeatureConstants.mapLayerLink: layerLink,
      FeatureConstants.forceOfflineMap: forceOfflineMap,
    };
    if (offlineMapPackageURL != null) {
      data[FeatureConstants.offlineMapPackageURL] = offlineMapPackageURL!;
    }
    if (offlineMapStyleURL != null) {
      data[FeatureConstants.offlineMapStyleURL] = offlineMapStyleURL!;
    }
    if (offlineMapLayerName != null) {
      data[FeatureConstants.offlineMapLayerName] = offlineMapLayerName!;
    }
    data[FeatureConstants.offlineMapRenderer] = offlineMapRenderer.wireValue;
    if (offlineMapBundleManifestURL != null) {
      data[FeatureConstants.offlineMapBundleManifestURL] =
          offlineMapBundleManifestURL!;
    }
    return data;
  }
}

bool _hasText(Object? value) => value is String && value.trim().isNotEmpty;
