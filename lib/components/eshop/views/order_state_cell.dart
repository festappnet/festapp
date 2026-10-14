import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';
import 'order_bank_sync_warning.dart';

class OrderStateCell extends StatelessWidget {
  final String label;
  final Color background;
  final OrderModel? order;
  final bool expired;
  const OrderStateCell(
      {super.key,
      required this.label,
      required this.background,
      this.order,
      this.expired = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Tooltip(
                message: label,
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
            if (order case final order? when order.bankSyncWarning != null) ...[
              const SizedBox(width: 4),
              OrderBankSyncWarning(order: order),
            ],
            if (expired)
              Padding(
                padding: const EdgeInsets.only(left: 4.0),
                child: Tooltip(
                  message: OrdersStrings.expiredOrderTooltip,
                  child: CircleAvatar(
                    radius: 10,
                    backgroundColor: ThemeConfig.redColor(context),
                    child: const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
