import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Location configuration used while a map is visible on a mobile device.
abstract final class MapLocationAccuracy {
  static const iosTemporaryFullAccuracyPurposeKey = 'MapLocation';
  static Future<bool>? _permissionCheck;

  static const settings = LocationSettings(
    accuracy: LocationAccuracy.bestForNavigation,
    distanceFilter: 0,
  );

  static Stream<Position> positionStream() async* {
    if (!await ensurePermission()) return;
    yield* Geolocator.getPositionStream(locationSettings: settings);
  }

  static Future<Position?> currentPosition() async {
    if (!await ensurePermission()) return null;
    return Geolocator.getCurrentPosition(locationSettings: settings);
  }

  static Future<bool> ensurePermission() async {
    final pending = _permissionCheck;
    if (pending != null) return pending;
    final check = _ensurePermission();
    _permissionCheck = check;
    try {
      return await check;
    } finally {
      if (identical(_permissionCheck, check)) _permissionCheck = null;
    }
  }

  static Future<bool> _ensurePermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return false;
    }
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final accuracy = await Geolocator.getLocationAccuracy();
      if (accuracy == LocationAccuracyStatus.reduced) {
        await Geolocator.requestTemporaryFullAccuracy(
          purposeKey: iosTemporaryFullAccuracyPurposeKey,
        );
      }
    }
    return true;
  }
}
