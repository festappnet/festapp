import 'package:flutter/foundation.dart';

import 'js/js_interop.dart';

/// Browser-side lifecycle boundary for the Flutter application shell.
///
/// The JavaScript loader can only prove that the Flutter engine started. The
/// app reports readiness separately, after startup completed and the first
/// usable frame was painted, so PWA recovery can distinguish a healthy app
/// from an engine that is stuck on the startup screen.
class WebBootstrapBridge {
  static final JSInterop _jsInterop = JSInterop();
  static String startupPhase = 'S00';

  static void retryStartup() {
    if (kIsWeb) _jsInterop.callMethod('retryFestappStartup', const []);
  }

  /// Fixed phase codes only; no route, account, session or exception details.
  static void markStartupPhase(String phase) {
    startupPhase = phase;
    if (kIsWeb) {
      _jsInterop.callMethod('setFestappStartupPhase', [phase]);
    }
  }

  static void markAppReady() {
    if (kIsWeb) {
      _jsInterop.callMethod('markFestappAppReady', const []);
    }
  }
}
