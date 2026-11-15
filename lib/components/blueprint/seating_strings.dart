import 'package:fstapp/components/eshop/order_item_strings.dart';
import 'package:easy_localization/easy_localization.dart';

class SeatingStrings {
  static String text(String key) => OrderItemStrings.text('Seating.$key');
  static String reason(String key) {
    final lookup = 'Seating.$key';
    return trExists(lookup) ? OrderItemStrings.text(lookup) : text('UNKNOWN');
  }
}
