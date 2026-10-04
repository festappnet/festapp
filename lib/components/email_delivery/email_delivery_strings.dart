import 'package:easy_localization/easy_localization.dart';

class EmailDeliveryStrings {
  static String get title => 'EmailDelivery.title'.tr();
  static String get organizationScope =>
      'EmailDelivery.organization_scope'.tr();
  static String refreshed(String time) =>
      'EmailDelivery.refreshed'.tr(namedArgs: {'time': time});
  static String get history => 'EmailDelivery.history'.tr();
  static String get unavailable => 'EmailDelivery.state.unavailable'.tr();
  static String state(String value) => 'EmailDelivery.state.$value'.tr();
  static String kind(String value) => 'EmailDelivery.kind.$value'.tr();
}
