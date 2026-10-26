import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/map_location_accuracy.dart';
import 'package:geolocator/geolocator.dart';

final class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  _FakeGeolocatorPlatform({required this.permission, required this.position});

  LocationPermission permission;
  final Position position;
  int positionRequests = 0;
  LocationSettings? receivedSettings;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async => permission;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    positionRequests++;
    receivedSettings = locationSettings;
    return position;
  }
}

void main() {
  final position = Position(
    longitude: 14.4378,
    latitude: 50.0755,
    timestamp: DateTime(2026),
    accuracy: 1,
    altitude: 0,
    altitudeAccuracy: 1,
    heading: 0,
    headingAccuracy: 1,
    speed: 0,
    speedAccuracy: 1,
  );

  test('open mobile map requests maximum continuous location accuracy', () {
    expect(
      MapLocationAccuracy.iosTemporaryFullAccuracyPurposeKey,
      'MapLocation',
    );
    expect(
      MapLocationAccuracy.settings.accuracy,
      LocationAccuracy.bestForNavigation,
    );
    expect(MapLocationAccuracy.settings.distanceFilter, 0);
  });

  test('current position uses the navigation-grade settings', () async {
    final original = GeolocatorPlatform.instance;
    final fake = _FakeGeolocatorPlatform(
      permission: LocationPermission.whileInUse,
      position: position,
    );
    GeolocatorPlatform.instance = fake;
    addTearDown(() => GeolocatorPlatform.instance = original);

    expect(await MapLocationAccuracy.currentPosition(), same(position));
    expect(fake.positionRequests, 1);
    expect(fake.receivedSettings, same(MapLocationAccuracy.settings));
  });

  test('denied current position does not ask the platform for a fix', () async {
    final original = GeolocatorPlatform.instance;
    final fake = _FakeGeolocatorPlatform(
      permission: LocationPermission.deniedForever,
      position: position,
    );
    GeolocatorPlatform.instance = fake;
    addTearDown(() => GeolocatorPlatform.instance = original);

    expect(await MapLocationAccuracy.currentPosition(), isNull);
    expect(fake.positionRequests, 0);
  });
}
