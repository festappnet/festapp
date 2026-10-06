import 'product_model.dart';

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

  static List<OrderTicketChange> _tickets(dynamic value) => (value as List)
      .map((t) => OrderTicketChange.fromJson(Map<String, dynamic>.from(t)))
      .toList();
}

class OrderTicketChange {
  final int? id;
  final String? ticketSymbol;
  final List<ProductModel> products;
  final List<ProductModel> added;
  final List<ProductModel> removed;
  final List<({ProductModel from, ProductModel to})> changed;

  OrderTicketChange.fromJson(Map<String, dynamic> json)
      : id = (json['id'] as num?)?.toInt(),
        ticketSymbol = json['ticket_symbol'] as String?,
        products = _products(json['products']),
        added = _products(json['added']),
        removed = _products(json['removed']),
        changed = (json['changed'] as List? ?? [])
            .map((c) => (from: _product(c['from']), to: _product(c['to'])))
            .toList();

  static List<ProductModel> _products(dynamic value) =>
      (value as List? ?? []).map(_product).toList();

  static ProductModel _product(dynamic value) => ProductModel(
        id: value['id'],
        title: value['title'],
        price: (value['price'] as num?)?.toDouble() ?? 0,
        currencyCode: value['currency_code'],
      );
}
