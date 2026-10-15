import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/external_map_navigation.dart';

void main() {
  const latitude = 49.8209;
  const longitude = 18.2625;

  test('builds walking navigation links for supported iOS apps', () {
    final apple = ExternalMapNavigation.destinationUri(
      app: IosNavigationApp.appleMaps,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
    );
    final google = ExternalMapNavigation.destinationUri(
      app: IosNavigationApp.googleMaps,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
    );
    final waze = ExternalMapNavigation.destinationUri(
      app: IosNavigationApp.waze,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
    );
    final mapy = ExternalMapNavigation.destinationUri(
      app: IosNavigationApp.mapyCom,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
    );

    expect(apple.toString(),
        'https://maps.apple.com/?daddr=49.8209%2C18.2625&dirflg=w');
    expect(google.toString(),
        'comgooglemaps://?daddr=49.8209%2C18.2625&directionsmode=walking');
    expect(waze.toString(), 'waze://?ll=49.8209%2C18.2625&navigate=yes');
    expect(
      mapy.toString(),
      'https://mapy.com/fnc/v1/route?end=18.2625%2C49.8209&routeType=foot_fast&navigate=true',
    );
  });

  test('only lists installed apps that require custom URL schemes', () async {
    final apps = await ExternalMapNavigation.availableIosApps(
      checker: (uri) async => uri.scheme == 'comgooglemaps',
    );

    expect(
      apps,
      [
        IosNavigationApp.appleMaps,
        IosNavigationApp.mapyCom,
        IosNavigationApp.googleMaps,
      ],
    );
  });

  test('falls back through system navigation to Apple Maps', () async {
    final attempts = <Uri>[];
    final opened = await ExternalMapNavigation.launchIos(
      app: IosNavigationApp.googleMaps,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
      launcher: (uri) async {
        attempts.add(uri);
        if (uri.scheme == 'comgooglemaps') throw StateError('not installed');
        return uri.scheme == 'https';
      },
    );

    expect(opened, isTrue);
    expect(
      attempts.map((uri) => uri.scheme),
      ['comgooglemaps', 'geo-navigation', 'https'],
    );
    expect(attempts[1].path, '/directions');
    expect(
      attempts[1].toString(),
      'geo-navigation:///directions?destination=49.8209%2C18.2625',
    );
  });

  test('returns false instead of throwing when every launcher fails', () async {
    final opened = await ExternalMapNavigation.launchIos(
      app: IosNavigationApp.waze,
      latitude: latitude,
      longitude: longitude,
      label: 'Main stage',
      launcher: (_) async => throw StateError('cannot open'),
    );

    expect(opened, isFalse);
  });
}
