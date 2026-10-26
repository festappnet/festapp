import 'package:url_launcher/url_launcher.dart';

typedef NavigationUriLauncher = Future<bool> Function(Uri uri);
typedef NavigationUriChecker = Future<bool> Function(Uri uri);

enum IosNavigationApp {
  appleMaps,
  googleMaps,
  waze,
  mapyCom,
}

/// Builds and safely opens navigation deep links used by the public map.
class ExternalMapNavigation {
  static Uri availabilityUri(IosNavigationApp app) => switch (app) {
        IosNavigationApp.googleMaps => Uri.parse('comgooglemaps://'),
        IosNavigationApp.waze => Uri.parse('waze://'),
        IosNavigationApp.appleMaps => Uri.parse('https://maps.apple.com'),
        IosNavigationApp.mapyCom => Uri.parse('https://mapy.com'),
      };

  static Uri destinationUri({
    required IosNavigationApp app,
    required double latitude,
    required double longitude,
    required String label,
  }) {
    final coordinates = '$latitude,$longitude';
    return switch (app) {
      IosNavigationApp.appleMaps => Uri.https('maps.apple.com', '/', {
          'daddr': coordinates,
          'dirflg': 'w',
        }),
      IosNavigationApp.googleMaps => Uri(
          scheme: 'comgooglemaps',
          host: '',
          queryParameters: {
            'daddr': coordinates,
            'directionsmode': 'walking',
          },
        ),
      IosNavigationApp.waze => Uri(
          scheme: 'waze',
          host: '',
          queryParameters: {
            'll': coordinates,
            'navigate': 'yes',
          },
        ),
      IosNavigationApp.mapyCom => Uri.https('mapy.com', '/fnc/v1/route', {
          'end': '$longitude,$latitude',
          'routeType': 'foot_fast',
          'navigate': 'true',
        }),
    };
  }

  static Uri systemDestinationUri({
    required double latitude,
    required double longitude,
  }) =>
      Uri(
        scheme: 'geo-navigation',
        host: '',
        path: '/directions',
        queryParameters: {'destination': '$latitude,$longitude'},
      );

  static Future<List<IosNavigationApp>> availableIosApps({
    NavigationUriChecker checker = canLaunchUrl,
  }) async {
    final apps = <IosNavigationApp>[
      IosNavigationApp.appleMaps,
      IosNavigationApp.mapyCom,
    ];
    for (final app in [
      IosNavigationApp.googleMaps,
      IosNavigationApp.waze,
    ]) {
      try {
        if (await checker(availabilityUri(app))) apps.add(app);
      } catch (_) {
        // A failed availability query must not prevent navigation altogether.
      }
    }
    return apps;
  }

  static Future<bool> launchIos({
    required IosNavigationApp app,
    required double latitude,
    required double longitude,
    required String label,
    NavigationUriLauncher launcher = _launch,
  }) async {
    final selected = destinationUri(
      app: app,
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
    final system = systemDestinationUri(
      latitude: latitude,
      longitude: longitude,
    );
    final apple = destinationUri(
      app: IosNavigationApp.appleMaps,
      latitude: latitude,
      longitude: longitude,
      label: label,
    );
    final candidates = <Uri>[selected, system];
    if (apple != selected) candidates.add(apple);

    for (final candidate in candidates) {
      try {
        if (await launcher(candidate)) return true;
      } catch (_) {
        // Continue through the system and Apple Maps fallbacks.
      }
    }
    return false;
  }

  static Future<bool> _launch(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}
