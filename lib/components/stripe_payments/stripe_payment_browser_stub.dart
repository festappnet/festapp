import 'package:flutter/foundation.dart';
import 'stripe_payment_link_service.dart';

Map<String, String>? consumeStripePaymentLink({String? expectedKind}) =>
    StripePaymentLinkService.inbox.consume(expectedKind: expectedKind);
Listenable? get stripePaymentLinkChanges => StripePaymentLinkService.revision;
void rememberStripePaymentLink(String token, {String? payUrl}) {}
String stripePaymentSurface() => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      _ => 'unsupported'
    };

Uri? stripeHandoffUri(String? value, String? token) => null;
