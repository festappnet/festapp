import 'package:easy_localization/easy_localization.dart';
import '../features/ticket_feature.dart';

class TicketDeliveryStrings {
  static String text(String key) => 'TicketDelivery.$key'.tr();
  static String label(TicketDeliveryMode mode) => text(mode.value);
  static String description(TicketDeliveryMode mode) =>
      text('${mode.value}Help');
}
