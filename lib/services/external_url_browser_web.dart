import 'package:web/web.dart' as web;

void openExternalUrlInBrowser(
  String url, {
  required bool inCurrentWindow,
}) {
  if (inCurrentWindow) {
    web.window.location.href = url;
    return;
  }
  web.window.open(url, '_blank', 'noopener,noreferrer');
}
