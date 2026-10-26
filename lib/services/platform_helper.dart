import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pwa_install/pwa_install.dart';

class PlatformHelper {
  /// Measurement metadata is self-reported and never grants write permission.
  /// An unavailable package plugin must not prevent backend initialization.
  static Future<Map<String, String>> getBackendRequestHeaders() async {
    final platform = kIsWeb ? 'web' : defaultTargetPlatform.name;
    try {
      final info = await PackageInfo.fromPlatform();
      return {
        'X-Client-Info': 'festapp/${info.version}+${info.buildNumber}/$platform',
      };
    } catch (_) {
      return {'X-Client-Info': 'festapp/unknown/$platform'};
    }
  }

  static Future<Map<String, dynamic>> getPlatform() async {
    var packageInfo = await PackageInfo.fromPlatform();
    var version = packageInfo.version;
    String platform;

    if (isWebBasic) {
      platform = 'web';
    } else if (isPwa) {
      platform = 'pwa';
    } else if (Platform.isIOS) {
      platform = 'ios';
    } else if (Platform.isAndroid) {
      platform = 'droid';
    } else {
      platform = 'unknown';
    }

    String buildMode;
    if (kDebugMode) {
      buildMode = 'debug';
    } else if (kReleaseMode) {
      buildMode = 'release';
    } else {
      buildMode = 'profile';
    }

    return {
      'platform': platform,
      'version': version,
      'buildNumber': packageInfo.buildNumber,
      'buildMode': buildMode,
    };
  }

  static bool get isIOS => defaultTargetPlatform == TargetPlatform.iOS;
  static bool get isAndroid => defaultTargetPlatform == TargetPlatform.android;
  static bool get isWeb => kIsWeb;
  static bool get isWasm => identical(double.nan, double.nan);
  static bool get isWebBasic => kIsWeb && !PWAInstall().launchMode!.installed;
  static bool get isPwa => kIsWeb && PWAInstall().launchMode!.installed;
  static bool get isNative =>
      !(const bool.fromEnvironment('dart.library.js_util') ||
          const bool.fromEnvironment('dart.library.js_interop'));
  static bool isPwaInstalledOrNative() => isNative || isPwa;
}
