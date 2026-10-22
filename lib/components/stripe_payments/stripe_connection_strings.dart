import 'package:easy_localization/easy_localization.dart';

class StripeConnectionStrings {
  static String text(String key) => 'CardPaymentConnection.$key'.tr();
  static String get title => text('title');
}
