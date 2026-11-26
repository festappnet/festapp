import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:easy_localization/easy_localization.dart';

class PaymentMethodStrings {
  static String text(String key, {bool? hasTickets}) =>
      OrderItemStrings.text('PaymentMethods.$key', hasTickets: hasTickets);
  static String gateway(String name) =>
      'PaymentMethods.gatewayName'.tr(namedArgs: {'name': name});
  static String recipient(String name) =>
      'PaymentMethods.recipient'.tr(namedArgs: {'name': name});
  static String reservation(int seconds) => 'PaymentMethods.reservation'.tr(
    namedArgs: {'minutes': (seconds / 60).ceil().toString()},
  );
  static const _reasons = {
    'not_configured',
    'paused',
    'stripe_restricted',
    'provider_restricted',
    'model_unverified',
    'recipient_changed',
    'payments_disabled',
    'return_origin_unavailable',
    'currency_unsupported',
    'mixed_currencies',
    'deposit_unsupported',
    'surcharge_unsupported',
    'fakturoid_unsupported',
    'sale_ending',
    'surface_unverified',
    'organizer_unavailable',
  };
  static String reason(String? value) =>
      text('reason_${_reasons.contains(value) ? value : 'unavailable'}');
}
