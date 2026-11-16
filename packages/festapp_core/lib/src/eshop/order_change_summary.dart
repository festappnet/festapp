import 'package:festapp_core/eshop.dart';

/// Presentation of the canonical SQL change summary; no comparison logic here.
class OrderChangeSummary {
  final List<OrderTicketChange> cancelledTickets;
  final List<OrderTicketChange> removedTickets;
  final List<OrderTicketChange> addedTickets;
  final List<OrderTicketChange> productChanges;
  final double referenceTotal;
  final double currentTotal;
  final bool hasChanges;
  final String currencyCode;

  OrderChangeSummary.fromJson(Map<String, dynamic> json)
    : cancelledTickets = _tickets(json['cancelledTickets']),
      removedTickets = _tickets(json['removedTickets']),
      addedTickets = _tickets(json['addedTickets']),
      productChanges = _tickets(json['productChanges']),
      referenceTotal = (json['referenceTotal'] as num).toDouble(),
      currentTotal = (json['currentTotal'] as num).toDouble(),
      currencyCode = json['currencyCode'] as String,
      hasChanges = json['hasChanges'] == true {
    if (json['version'] != 1) {
      throw const FormatException('Unknown order change summary');
    }
  }

  bool hasChangesOutside(int ticketId) => [
    ...cancelledTickets,
    ...removedTickets,
    ...addedTickets,
    ...productChanges,
  ].any((ticket) => ticket.id != ticketId);

  static List<OrderTicketChange> _tickets(dynamic value) => List.unmodifiable(
    (value as List).map(
      (t) => OrderTicketChange.fromJson(Map<String, dynamic>.from(t)),
    ),
  );
}

class OrderTicketChange {
  final int? id;
  final String? ticketSymbol;
  final List<OrderChangeProduct> products;
  final List<OrderChangeProduct> added;
  final List<OrderChangeProduct> removed;
  final List<({OrderChangeProduct from, OrderChangeProduct to})> changed;

  OrderTicketChange.fromJson(Map<String, dynamic> json)
    : id = (json['id'] as num?)?.toInt(),
      ticketSymbol = json['ticket_symbol'] as String?,
      products = _products(json['products']),
      added = _products(json['added']),
      removed = _products(json['removed']),
      changed = List.unmodifiable(
        (json['changed'] as List? ?? []).map(
          (c) => (from: _product(c['from']), to: _product(c['to'])),
        ),
      );

  static List<OrderChangeProduct> _products(dynamic value) =>
      List.unmodifiable((value as List? ?? []).map(_product));

  static OrderChangeProduct _product(dynamic value) =>
      OrderChangeProduct.fromJson(Map<String, dynamic>.from(value));
}

/// Purchased product snapshot with the seating facts used in customer updates.
class OrderChangeProduct extends ProductModel {
  final String? spotTitle;
  final String? spotGroupTitle;

  OrderChangeProduct.fromJson(Map<String, dynamic> json)
    : spotTitle = json['spot_title'] as String?,
      spotGroupTitle = json['spot_group_title'] as String?,
      super(
        id: json['id'],
        title: json['title'],
        price: (json['price'] as num?)?.toDouble() ?? 0,
        currencyCode: json['currency_code'],
      );

  String get seatLabel => [
    spotGroupTitle,
    spotTitle,
  ].whereType<String>().where((part) => part.isNotEmpty).join(' / ');
}
