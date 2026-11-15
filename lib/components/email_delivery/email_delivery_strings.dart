import 'package:easy_localization/easy_localization.dart';
import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:fstapp/data_services/rights_service.dart';

class EmailDeliveryStrings {
  static String recovery(String key) => 'EmailDelivery.recovery.$key'.tr();
  static String get title => 'EmailDelivery.title'.tr();
  static String get organizationScope =>
      'EmailDelivery.organization_scope'.tr();
  static String refreshed(String time) =>
      'EmailDelivery.refreshed'.tr(namedArgs: {'time': time});
  static String get history => 'EmailDelivery.history'.tr();
  static String get unavailable => 'EmailDelivery.state.unavailable'.tr();
  static String state(String value) => 'EmailDelivery.state.$value'.tr();
  static String kind(String value) =>
      value == 'order_tickets' && RightsService.currentOccasion() != null
      ? OrderItemStrings.itemsPlural
      : 'EmailDelivery.kind.$value'.tr();
}
