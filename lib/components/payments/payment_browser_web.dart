import 'package:festapp_core/payments.dart';

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('__festappPaymentLink')
external JSString? get _link;
@JS('__festappPaymentLink')
external set _link(JSString? value);
String paymentSurface() => web.window.top == web.window ? 'web' : 'embed';

Listenable? get paymentLinkChanges => null;

Map<String, String>? consumePaymentLink({
  String? expectedKind,
  String? expectedProvider,
}) {
  final value = _link?.toDart;
  if (value == null) return null;
  final result = (jsonDecode(value) as Map).cast<String, String>();
  if (expectedProvider != null && result['provider'] != expectedProvider)
    return null;
  if (expectedKind != null &&
      result['kind'] != expectedKind &&
      !(expectedKind == 'pay' && result['kind'] == 'handoff'))
    return null;
  _link = null;
  return result;
}

void rememberPaymentLink(
  String token, {
  required PaymentConnector connector,
  String? payUrl,
}) {
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
  if (!uri.path.endsWith(connector.payPath)) return;
  final state = web.window.history.state.dartify();
  web.window.history.replaceState(
    {
      if (state is Map) ...state.cast<String, dynamic>(),
      'festappPayment': {
        'provider': connector.id,
        'kind': 'pay',
        'token': token,
      },
    }.jsify(),
    '',
    uri.replace(fragment: '').toString(),
  );
}

Uri? paymentHandoffUri(
  String? value,
  String? token, {
  PaymentConnector? connector,
}) {
  if (connector == null ||
      value == null ||
      token == null ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(token))
    return null;
  final uri = Uri.tryParse(value),
      current = Uri.parse(web.window.location.href);
  return uri != null &&
          uri.scheme == 'https' &&
          uri.origin == current.origin &&
          uri.userInfo.isEmpty &&
          uri.query.isEmpty &&
          uri.path.endsWith(connector.payPath) &&
          uri.fragment == 'handoff=$token'
      ? uri
      : null;
}
