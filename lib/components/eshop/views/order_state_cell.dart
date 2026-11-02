import 'package:fstapp/components/email_delivery/email_delivery_issue_icon.dart';

import 'order_email_repair_dialog.dart';

import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';

import 'order_bank_sync_warning.dart';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/theme_config.dart';

import '../models/order_model.dart';
import '../orders_strings.dart';

class OrderStateCell extends StatelessWidget {
  final VoidCallback? onOpenEmails;
  final String label;
  final Color background;
  final OrderModel? order;
  final bool expired;
  final int? occasionId;
  final Future<void> Function()? onChanged;
  const OrderStateCell({
    super.key,
    required this.label,
    required this.background,
    this.order,
    this.expired = false,
    this.onChanged,
    this.occasionId,
    this.onOpenEmails,
  });

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
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  visualDensity: VisualDensity.standard,
                  style: IconButton.styleFrom(
                    minimumSize: const Size(20, 20),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  constraints: const BoxConstraints.tightFor(
                    width: 20,
                    height: 20,
                  ),
                  padding: EdgeInsets.zero,
                  tooltip:
                      '${issues.map((i) => i.tooltipDescription).join('\n')}\n${EmailDeliveryStrings.recovery('resolveHint')}',
                  icon: EmailDeliveryIssueIcon(count: issues.length),
                  onPressed:
                      onOpenEmails ??
                      () => showDialog<void>(
                        context: context,
                        builder: (_) => OrderEmailRepairDialog(
                          orderId: order!.id!,
                          occasionId: scopeOccasion,
                          onChanged: onChanged,
                        ),
                      ),
                ),
              ),
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
