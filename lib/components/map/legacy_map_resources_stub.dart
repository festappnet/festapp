import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/offline_map_bundle_manager.dart';

/// Web placeholder for the native-only MBTiles resources.
class LegacyMapResources {
  static Future<LegacyMapResources> open({
    required String styleUri,
    required String mbtilesPath,
  }) =>
      Future.error(
        UnsupportedError('Offline MBTiles are unavailable on the web.'),
      );

  static Future<LegacyMapResources> openBundle(
    OfflineMapBundleInstallation installation,
  ) =>
      Future.error(
        UnsupportedError('Offline MBTiles are unavailable on the web.'),
      );

  Widget buildBaseLayer({
    required String sourceName,
    required double maximumZoom,
  }) =>
      const SizedBox.shrink();

  void dispose() {}
}
