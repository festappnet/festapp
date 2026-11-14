import 'package:fstapp/components/eshop/order_item_strings.dart';

class CardPaymentStrings {
  static String text(String key, {bool? hasTickets}) =>
      OrderItemStrings.text('CardPayments.$key', hasTickets: hasTickets);
}
