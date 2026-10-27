abstract interface class ExternalUrlWindow {
  void navigate(String url);
  void close();
}

/// Reserve the window during the click, before waiting for a server URL.
Future<bool> openDeferredExternalUrl(
  Future<String> Function() resolveUrl,
  ExternalUrlWindow? Function() openWindow,
) async {
  final window = openWindow();
  if (window == null) {
    throw StateError('The browser blocked opening a new tab.');
  }
  try {
    window.navigate(await resolveUrl());
    return true;
  } catch (_) {
    window.close();
    rethrow;
  }
}
