import 'package:easy_localization/easy_localization.dart';

/// Localized strings for the map feature (map page, places, path drawing).
/// Keys live under the "FeatureMap" namespace in assets/translations/*.json.
class MapStrings {
  static const appleMaps = 'Apple Maps';
  static const googleMaps = 'Google Maps';
  static const waze = 'Waze';
  static const mapyCom = 'Mapy.com';

  // Places / locations
  static String get changeLocation =>
      'FeatureMap.changeLocation'.tr(); // "Change location"
  static String get changeLocationHint => 'FeatureMap.changeLocationHint'
      .tr(); // "You can change location by tapping on the map."
  static String get locationOnMap =>
      'FeatureMap.locationOnMap'.tr(); // "Location on map"
  static String get currentLocation =>
      'FeatureMap.currentLocation'.tr(); // "My location"
  static String get currentLocationUnavailable =>
      'FeatureMap.currentLocationUnavailable'.tr();
  static String get placeChanged =>
      'FeatureMap.placeChanged'.tr(); // "Place has been changed."
  static String get showGroups => 'FeatureMap.showGroups'.tr(); // "Show groups"
  static String get saveLocation =>
      'FeatureMap.saveLocation'.tr(); // "Save location"
  static String get navigate => 'FeatureMap.navigate'.tr(); // "Navigate"
  static String get chooseNavigationApp =>
      'FeatureMap.chooseNavigationApp'.tr(); // "Choose navigation app"
  static String get loadingMap =>
      'FeatureMap.loadingMap'.tr(); // "Loading map…"
  static String get counselingHours =>
      'FeatureMap.counselingHours'.tr(); // "Counseling hours"

  // Paths / route drawing
  static String get paths => 'FeatureMap.paths'.tr(); // "Paths"
  static String get drawPath => 'FeatureMap.drawPath'.tr(); // "Draw path"
  static String get drawPathHint => 'FeatureMap.drawPathHint'
      .tr(); // "Tap places or the map to add points to the path."
  static String get importRoute =>
      'FeatureMap.importRoute'.tr(); // "Import route"
  static String get importRouteHint => 'FeatureMap.importRouteHint'
      .tr(); // "Export your route from Mapy.com (or Strava, Garmin, komoot…) as GPX and drop it here."
  static String get undo => 'FeatureMap.undo'.tr(); // "Undo"
  static String get newSegment => 'FeatureMap.newSegment'.tr(); // "New segment"
  static String get saveRoute => 'FeatureMap.saveRoute'.tr(); // "Save route"
  static String get noRouteInGpx =>
      'FeatureMap.noRouteInGpx'.tr(); // "No route found in the GPX file."

  // Offline map
  static String get offlineMapReady => 'FeatureMap.offlineMapReady'
      .tr(); // "Offline map downloaded and ready for offline use"
  static String get offlineMapConfigurationIncomplete =>
      'FeatureMap.offlineMapConfigurationIncomplete'.tr();
  static String get mapLibreManifestNotConfigured =>
      'FeatureMap.mapLibreManifestNotConfigured'.tr();
  static String get mapLibreNotDownloaded =>
      'FeatureMap.mapLibreNotDownloaded'.tr();
  static String get downloadMapAgain => 'FeatureMap.downloadMapAgain'.tr();
  static String get mapLibreBundleDownloadFailed =>
      'FeatureMap.mapLibreBundleDownloadFailed'.tr();
  static const openStreetMapAttribution = '© OpenStreetMap contributors';
}
