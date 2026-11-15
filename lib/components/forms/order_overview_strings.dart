import 'package:fstapp/components/eshop/order_item_strings.dart';

class OrderOverviewStrings {
  static String text(String key, {bool? hasTickets}) =>
      OrderItemStrings.text('OrderOverview.$key', hasTickets: hasTickets);
}
