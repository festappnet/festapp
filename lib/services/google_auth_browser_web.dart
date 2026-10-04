import 'package:web/web.dart' as web;

const _key = 'festapp-google-attempt-v1';
Uri? consumeGoogleBrowserCallback() {
  final uri = Uri.parse(web.window.location.href);
  if (!uri.queryParameters.containsKey('google_code') &&
      !uri.queryParameters.containsKey('google_error')) {
    return null;
  }
  final params = Map<String, String>.from(uri.queryParameters)
    ..remove('google_code')
    ..remove('google_attempt')
    ..remove('google_error');
  final clean = uri.replace(
      queryParameters: params.isEmpty ? null : params,
      query: params.isEmpty ? '' : null);
  web.window.history.replaceState(null, '', clean.toString());
  return uri;
}

String? readGoogleBrowserAttempt() => web.window.sessionStorage.getItem(_key);
void writeGoogleBrowserAttempt(String value) =>
    web.window.sessionStorage.setItem(_key, value);
void clearGoogleBrowserAttempt() => web.window.sessionStorage.removeItem(_key);
