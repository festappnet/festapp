import 'package:easy_localization/easy_localization.dart';

class CardRefundDecisionStrings {
  static String text(String key) => 'CardRefundDecision.$key'.tr();
  static String amount(int minor, String currency, {String? locale}) =>
      NumberFormat.simpleCurrency(
              locale: locale ?? Intl.getCurrentLocale(),
              name: currency,
              decimalDigits: 2)
          .format(minor / 100);
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
