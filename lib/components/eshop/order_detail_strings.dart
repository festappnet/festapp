import 'package:easy_localization/easy_localization.dart';

abstract final class OrderDetailStrings {
  static String text(String key) => 'OrderDetail.$key'.tr();

  // Explicit integer forms retain Czech 'few' even when the app uses the
  // localization package's default ignorePluralRules setting.
  static String count(String key, int count) {
    final category = count == 0
        ? 'zero'
        : count == 1
        ? 'one'
        : count >= 2 && count <= 4
        ? 'few'
        : 'other';
    return 'OrderDetail.${key}_$category'.tr(namedArgs: {'count': '$count'});
  }
}
