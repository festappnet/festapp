import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/tb_eshop.dart';

class OrderProductTicketModel {
  int? id;
  DateTime? createdAt;
  int? orderId;
  int? productId;
  int? ticketId;

  OrderModel? order;

  OrderProductTicketModel({
    this.id,
    this.createdAt,
    this.orderId,
    this.productId,
    this.ticketId,
    this.order,
  });

  factory OrderProductTicketModel.fromJson(Map<String, dynamic> json) {
    final t = TbEshop.order_product_ticket;
    return OrderProductTicketModel(
      id: json[t.id],
      createdAt: json[t.created_at] != null
          ? DateTime.parse(json[t.created_at])
          : null,
      orderId: json[t.order],
      productId: json[t.product],
      ticketId: json[t.ticket],
    );
  }

  Map<String, dynamic> toJson() {
    final t = TbEshop.order_product_ticket;
    return {
      t.id: id,
      t.created_at: createdAt?.toIso8601String(),
      t.order: orderId,
      t.product: productId,
      t.ticket: ticketId,
    };
  }

  String toBasicString() => "OrderProductTicket #${id ?? ''}";
}
