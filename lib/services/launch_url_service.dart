import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:url_launcher/url_launcher.dart';

import 'external_url_browser_stub.dart'
    if (dart.library.html) 'external_url_browser_web.dart'
    if (dart.library.js_interop) 'external_url_browser_web.dart';

class LaunchUrlService {
  static Future<bool> openExternalUrl(
    String url, {
    bool inCurrentWindow = false,
  }) {
    final uri = Uri.tryParse(url);
    if (uri == null) return Future.value(false);

    if (kIsWeb) {
      openExternalUrlInBrowser(
        url,
        inCurrentWindow: inCurrentWindow,
      );
      return Future.value(true);
    }

    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
