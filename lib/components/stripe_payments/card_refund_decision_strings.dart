import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:festapp_core/formatting.dart';
import 'package:easy_localization/easy_localization.dart';

class CardRefundDecisionStrings {
  static String text(String key) =>
      OrderItemStrings.text('CardRefundDecision.$key');
  static String amount(int minor, String currency, {String? locale}) =>
      formatDisplayCurrency(
        minor / 100,
        locale: locale ?? Intl.getCurrentLocale(),
        name: currency,
        decimalDigits: 2,
        simple: true,
      );

  static String error(Object error) {
    final code = error.toString();
    if (code.contains('STRIPE_REFUND_REVISION_CHANGED')) {
      return text('revisionChanged');
    }
    if (code.contains('STRIPE_REFUND_TICKET_UNAVAILABLE')) {
      return text('ticketUnavailable');
    }
    if (code.contains('STRIPE_PARTIAL_REFUND_REQUIRED')) {
      return text('notPartial');
    }
    return text('failed');
  }
}
