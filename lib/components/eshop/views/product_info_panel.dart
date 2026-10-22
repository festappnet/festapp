import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:fstapp/components/eshop/models/payment_info_model.dart';
import 'package:fstapp/components/eshop/models/ticket_model.dart';
import 'package:fstapp/services/utilities_all.dart';

import '../orders_strings.dart';

class ProductInfoPanel extends StatelessWidget {
  final OrderModel order;
  final PaymentInfoModel? paymentInfo;
  final TicketModel ticket;
  final OrderHistoryInfo orderHistory;
  final VoidCallback? onSendUpdate;

  const ProductInfoPanel({
    super.key,
    required this.order,
    required this.paymentInfo,
    required this.ticket,
    required this.orderHistory,
    this.onSendUpdate,
  });

  @override
  Widget build(BuildContext context) {
    final totalPaid = paymentInfo?.paid ?? 0;
    final orderPrice = order.price ?? 0;
    final isFullyPaid = totalPaid >= orderPrice && orderPrice > 0;

    return Column(
      children: [
        _buildInfoRow(
            context, OrdersStrings.infoTicketSymbol, ticket.ticketSymbol ?? "N/A"),
        _buildInfoRow(
            context, OrdersStrings.infoEmail, order.data?["email"] ?? "N/A"),
        _buildInfoRow(context, OrdersStrings.infoOrderStatus,
            OrderModel.stateToLocale(order.state!)),
        _buildInfoRow(
            context,
            OrdersStrings.infoPayment,
            "${Utilities.formatPrice(context, totalPaid)} / ${Utilities.formatPrice(context, orderPrice)}",
            valueColor: isFullyPaid ? Colors.green : Colors.orange.shade700),
        if (orderHistory.isNewerVersionAvailable)
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Card(
              color: Colors.amber.withOpacity(0.1),
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.warning_amber_rounded,
                          color: Colors.amber.shade800),
                      title: Text(OrdersStrings.outdatedTitle,
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade900)),
                      subtitle: Text(OrdersStrings.outdatedSubtitle),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: onSendUpdate,
                      icon: const Icon(Icons.email_outlined),
                      label: Text(OrdersStrings.sendUpdateButton),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade700,
                        foregroundColor: Colors.white,
                      ),
                    )
                  ],
                ),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value,
      {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          SelectableText(
            value,
            style: TextStyle(
                color: valueColor,
                fontWeight: valueColor != null ? FontWeight.bold : null),
          ),
        ],
      ),
    );
  }
}
