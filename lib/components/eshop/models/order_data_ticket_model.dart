import 'order_data_product_model.dart';

class OrderDataTicketModel {
  final int? id;
  final String? note;
  final String? ticketSymbol;
  final List<OrderDataProductModel> products;

  OrderDataTicketModel({
    this.id,
    this.note,
    this.ticketSymbol,
    required this.products,
  });

  factory OrderDataTicketModel.fromJson(Map<String, dynamic> json) {
    var productsList = <OrderDataProductModel>[];
    if (json['products'] is List) {
      productsList = (json['products'] as List)
          .map((p) => OrderDataProductModel.fromJson(p as Map<String, dynamic>))
          .toList();
    }

    return OrderDataTicketModel(
      id: json['id'],
      note: json['note'],
      ticketSymbol: json['ticket_symbol'],
      products: productsList,
    );
  }
}
