import 'package:festapp_core/time.dart';

import 'notification_timezone_stub.dart'
    if (dart.library.js_interop) 'notification_timezone_web.dart'
    as platform;

/// Web uses the browser's IANA zone. Native retains the application's selected
/// occasion timezone, owned and initialized by the shared time context.
class NotificationCenterTimezone {
  static String name() {
    final browser = platform.browserTimezone();
    if (browser != null) return browser;
    try {
      return OccasionTimeContext.local().location.name;
    } catch (_) {
      return OccasionTimeContext.defaultLocationName;
    }
  }
}
