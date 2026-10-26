import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('__festappStripeConnectCallback')
external JSString? get _callback;
@JS('__festappStripeConnectCallback')
external set _callback(JSString? value);
Map<String, String>? consumeStripeConnectionCallback() {
  final captured = _callback?.toDart;
  _callback = null;
  if (captured != null) {
    return (jsonDecode(captured) as Map).cast<String, String>();
  }
  final uri = Uri.parse(web.window.location.href);
  if (!uri.path.endsWith('/stripe/connect/callback')) return null;
  final values = {
    for (final key in ['code', 'state', 'error'])
      if (uri.queryParameters[key] != null) key: uri.queryParameters[key]!
  };
  if (values.isEmpty) return null;
  final clean = Map<String, String>.from(uri.queryParameters)
    ..remove('code')
    ..remove('state')
    ..remove('error')
    ..remove('error_description');
  web.window.history.replaceState(
      null,
      '',
      uri
          .replace(
              queryParameters: clean.isEmpty ? null : clean,
              query: clean.isEmpty ? '' : null)
          .toString());
  return values;
}
