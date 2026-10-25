import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/eshop/models/order_model.dart';
import 'package:trina_grid/trina_grid.dart';

/// Read-only renderer for ORDER_PRICE cell.
/// Shows the order price and, if the order uses deposit payment,
/// a chip with the deposit amount.
class OrderPriceDepositRenderer extends StatelessWidget {
  final TrinaColumnRendererContext rendererContext;
  final OrderModel order;

  const OrderPriceDepositRenderer({
    super.key,
    required this.rendererContext,
    required this.order,
  });

  @override
  Widget build(BuildContext context) {
    final priceVal = rendererContext.cell.value?.toString() ?? '';
    final depositAmount = order.paymentInfoModel?.depositAmount;
    final hasDeposit = depositAmount != null && depositAmount > 0;
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      alignment: Alignment.centerRight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            priceVal,
            style: hasDeposit
                ? const TextStyle(fontWeight: FontWeight.w500)
                : null,
          ),
          if (hasDeposit) ...[
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  width: 0.5,
                ),
              ),
              child: Text(
                _formatDeposit(depositAmount),
                style: TextStyle(
                  fontSize: 12,
                  height: 1.0,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _formatDeposit(double value) {
    if (value == value.truncateToDouble()) {
      return value.toInt().toString();
    }
    return value.toString();
  }
}
