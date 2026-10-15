import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/features_strings.dart';
import '../map_feature.dart';

extension MapFeatureSettingsEditor on MapFeature {
  Widget buildSettingsEditor(BuildContext context) {
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
