import 'package:web/web.dart' as web;

import 'deferred_external_url.dart';

ExternalUrlWindow? reserveExternalUrlWindow() {
  // noopener in window.open would discard the handle needed for navigation.
  final window = web.window.open('about:blank', '_blank');
  if (window == null) return null;
  window.opener = null;
  final referrer = web.HTMLMetaElement()
    ..name = 'referrer'
    ..content = 'no-referrer';
  window.document.head!.appendChild(referrer);
  return _BrowserExternalUrlWindow(window);
}

class _BrowserExternalUrlWindow implements ExternalUrlWindow {
  _BrowserExternalUrlWindow(this.window);
  final web.Window window;

  @override
  void navigate(String url) {
    if (window.closed) throw StateError('The new tab was closed.');
    window.location.replace(url);
  }

  @override
  void close() => window.close();
}

void openExternalUrlInBrowser(String url, {required bool inCurrentWindow}) {
  if (inCurrentWindow) {
    web.window.location.href = url;
    return;
  }
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
