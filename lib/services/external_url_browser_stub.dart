import 'deferred_external_url.dart';

ExternalUrlWindow? reserveExternalUrlWindow() => null;

void openExternalUrlInBrowser(String url, {required bool inCurrentWindow}) {
  throw UnsupportedError(
    'Browser navigation is not available on this platform.',
  );
}
