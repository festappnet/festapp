import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/widgets.dart';

class PublicOrderStrings {
  static const String _prefix = 'PublicOrder';

  static String _tr(String key, String? tone) {
    if (tone == 'informal') {
      final informalKey = '${key}_informal';
      if (informalKey.tr() != informalKey) {
        return informalKey.tr();
      }
    }
    return key.tr();
  }

  // Re-verify the logic:
  // If I call _tr('PublicOrder.successTitle', 'informal')
  // It checks 'PublicOrder.successTitle_informal'.

  static String successTitle(String? tone, {bool hasTickets = true}) {
    if (hasTickets) {
      return _tr('$_prefix.successTitle', tone);
    }
    return _tr('$_prefix.successRegistrationTitle', tone);
  }

  static String paymentInfo(String? tone) => _tr('$_prefix.paymentInfo', tone);

  static String confirmationInfo(String? tone, {required bool hasPayment, String email = '', String state = 'queued'}) {
    final key = hasPayment ? 'paymentInfo' : 'confirmationInfo';
    final suffix = state == 'accepted' ? 'Accepted' : ['failed','unknown','dead','suppressed','expired','cancelled','retry_wait'].contains(state) ? 'Unconfirmed' : '';
    final text = _tr('$_prefix.$key${email.isEmpty ? '' : 'WithEmail'}$suffix', tone);
    return email.isEmpty ? text : text.replaceAll('{email}', email);
  }

  static String selectSeat(String? tone) => _tr('$_prefix.selectSeat', tone);

  static String getSubmitButton(bool hasTickets, String? tone) {
    if (hasTickets) {
      return _tr('$_prefix.submitOrder', tone);
    }
    return _tr('$_prefix.submitRegistration', tone);
  }

  static String get summary => '$_prefix.summary'.tr();
  static String get backToForm => '$_prefix.backToForm'.tr();
  static String get orderFailed => '$_prefix.orderFailed'.tr();

  static String orderError(String code) =>
      '$_prefix.orderError'.tr(namedArgs: {"code": code});

  static String productUnavailable(String productTitle) =>
      '$_prefix.productUnavailable'.tr(
        namedArgs: {"product_title": productTitle},
      );

  static String chooseDifferentVariant(String? tone) =>
      _tr('$_prefix.chooseDifferentVariant', tone);

  static String totalPrice(BuildContext context, String price) =>
      '$_prefix.totalPrice'.tr(namedArgs: {"price": price});

  static String get paymentMethod => '$_prefix.paymentMethod'.tr();
  static String get payFullAmount => '$_prefix.payFullAmount'.tr();
  static String get payWithDeposit => '$_prefix.payWithDeposit'.tr();
  static String get depositInfoOnSite => '$_prefix.depositInfoOnSite'.tr();
  static String depositInfoDaysBefore(int days) =>
      '$_prefix.depositInfoDaysBefore'.tr(namedArgs: {"days": days.toString()});

  // Payment QR (shown on the order confirmation when the form enables it).
  static String get paymentQrTitle => '$_prefix.paymentQrTitle'.tr();
  static String get paymentQrSubtitle => '$_prefix.paymentQrSubtitle'.tr();
  static String get amountToPay => '$_prefix.amountToPay'.tr();
  static String get bankAccount => '$_prefix.bankAccount'.tr();
  static String get iban => '$_prefix.iban'.tr();
  static String get variableSymbol => '$_prefix.variableSymbol'.tr();
  static String get paymentReference => '$_prefix.paymentReference'.tr();
  static String get paymentNote => '$_prefix.paymentNote'.tr();
  static String get orderLabel => '$_prefix.orderLabel'.tr();
  static String get downloadQr => '$_prefix.downloadQr'.tr();
  static String get copied => '$_prefix.copied'.tr();
}
