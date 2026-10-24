import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

@JS('__festappStripePaymentLink')
external JSString? get _link;
@JS('__festappStripePaymentLink')
external set _link(JSString? value);
String stripePaymentSurface() => web.window.top == web.window ? 'web' : 'embed';

Listenable? get stripePaymentLinkChanges => null;

Map<String, String>? consumeStripePaymentLink({String? expectedKind}) {
  final value = _link?.toDart;
  _link = null;
  return value == null
      ? null
      : (jsonDecode(value) as Map).cast<String, String>();
}

void rememberStripePaymentLink(String token, {String? payUrl}) {
  // Same-origin history is a convenience for browser Back, never the sole
  // recovery source. The independently emailed encrypted source survives it.
  final current = Uri.parse(web.window.location.href);
  final uri = payUrl == null ? current : Uri.parse(payUrl);
  if (uri.origin != current.origin ||
      uri.query.isNotEmpty ||
      uri.userInfo.isNotEmpty ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
    return;
  }
  if (!uri.path.endsWith('/stripe/pay')) return;
  final state = web.window.history.state.dartify();
  web.window.history.replaceState(
      {
        if (state is Map) ...state.cast<String, dynamic>(),
        'festappStripePayment': {'kind': 'pay', 'token': token},
      }.jsify(),
      '',
      uri.replace(fragment: '').toString());
}

Uri? stripeHandoffUri(String? value, String? token) {
  if (value == null ||
      token == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) return null;
  final uri = Uri.tryParse(value),
      current = Uri.parse(web.window.location.href);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.origin == current.origin &&
          uri.userInfo.isEmpty &&
          uri.query.isEmpty &&
          uri.path.endsWith('/stripe/pay') &&
          uri.fragment == 'handoff=$token'
      ? uri
      : null;
}
