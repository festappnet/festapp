import 'package:easy_localization/easy_localization.dart';

class PaymentOperationStrings {
  static String bankQrError(String? code) => text(switch (code) {
    'SPD_DOMESTIC_ACCOUNT_REQUIRED' => 'qrDomesticAccountRequired',
    'PAYMENT_REFERENCE_ACCOUNT_INVALID' => 'invalidIban',
    'REFUND_AVAILABLE_EXCEEDED' => 'exceedsAvailable',
    'PAYMENT_AMOUNT_INVALID' => 'qrInvalidDetails',
    'REFUND_RECIPIENT_INVALID' => 'qrRecipientNameInvalid',
    'PAYMENT_CURRENCY_MISMATCH' => 'qrCurrencyChanged',
    'PAYMENT_REFUND_UNAVAILABLE' => 'bankUnavailable',
    'payment_refund_instructions_invalid' => 'qrInvalidDetails',
    _ => 'bankQrFailed',
  });

  static String text(String key) => 'PaymentOperations.$key'.tr();
}
