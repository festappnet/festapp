import 'package:festapp_core/payments.dart';
import 'package:flutter/foundation.dart';

import 'payment_link_service.dart';

Map<String, String>? consumePaymentLink({
  String? expectedKind,
  String? expectedProvider,
}) => PaymentLinkService.inbox.consume(
  expectedKind: expectedKind,
  expectedProvider: expectedProvider,
);
Listenable? get paymentLinkChanges => PaymentLinkService.revision;
void rememberPaymentLink(
  String token, {
  required PaymentConnector connector,
  String? payUrl,
}) {}
String paymentSurface() => switch (defaultTargetPlatform) {
  TargetPlatform.android => 'android',
  TargetPlatform.iOS => 'ios',
  _ => 'unsupported',
};

Uri? paymentHandoffUri(
  String? value,
  String? token, {
  PaymentConnector? connector,
}) => null;
