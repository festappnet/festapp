import 'order_email_repair_dialog.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'order_bank_sync_warning.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/theme_config.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';

class OrderStateCell extends StatelessWidget {
  final String label;
  final Color background;
  final OrderModel? order;
  final bool expired;
  final int? occasionId;
  final Future<void> Function()? onChanged;
  const OrderStateCell(
      {super.key,
      required this.label,
      required this.background,
      this.order,
      this.expired = false,
      this.onChanged,
      this.occasionId});

  @override
  Widget build(BuildContext context) {
    final scopeOccasion = occasionId ?? order?.occasion;
    final issues = OrderEmailIssue.fromSummary(order?.emailDelivery);
    return Container(
      color: background,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (order case final order? when order.bankSyncWarning != null) ...[
              const SizedBox(width: 4),
              OrderBankSyncWarning(order: order),
            ],
            if (issues.isNotEmpty && order?.id != null && scopeOccasion != null)
              IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  padding: EdgeInsets.zero,
                  tooltip:
                      '${issues.map((i) => i.description).join('\n')}\n${EmailDeliveryStrings.recovery('resolve')}',
                  icon: Badge(
                      isLabelVisible: issues.length > 1,
                      label: Text('${issues.length}'),
                      child: Icon(Icons.warning_amber_rounded,
                          size: 20,
                          color: issues.any((i) => i.isFailure)
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
                  onPressed: () => showDialog<void>(
                      context: context,
                      builder: (_) => OrderEmailRepairDialog(
                          orderId: order!.id!,
                          occasionId: scopeOccasion,
                          onChanged: onChanged))),
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
