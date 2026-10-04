import 'package:flutter/material.dart';
import '../models/product_model.dart';
import '../models/product_price_change.dart';
import '../orders_strings.dart';
import 'product_price_changes_dialog.dart';

class ProductPriceChangeCell extends StatelessWidget {
  final ProductModel product;
  final String timezone;
  final VoidCallback onOpen;
  final bool canEdit;
  final FocusNode? focusNode;
  const ProductPriceChangeCell(
      {super.key,
      required this.product,
      required this.timezone,
      required this.onOpen,
      this.canEdit = true,
      this.focusNode});
  @override
  Widget build(BuildContext context) {
    final plans = ProductPriceChange.pending(product.priceChanges);
    String summary =
        canEdit ? OrdersStrings.schedulePrice : OrdersStrings.priceChangesTitle;
    if (plans.isNotEmpty) {
      final first = plans.first;
      summary =
          '${scheduledPrice(context, product.price, product.currencyCode)} → ${scheduledPrice(context, first.price, product.currencyCode)} · ${scheduledTime(first.time, timezone)}';
      if (plans.length > 1) {
        summary += ' · ${priceChangeText(OrdersStrings.priceMore, [
              (plans.length - 1).toString()
            ])}';
      }
      if (first.failureCode != null) {
        summary += ' · ${OrdersStrings.priceFailed}';
      } else if (!first.time.isAfter(product.priceNow)) {
        summary += ' · ${OrdersStrings.pricePending}';
      }
    }
    final tooltip = plans.isEmpty
        ? summary
        : plans
            .map((p) =>
                '${scheduledPrice(context, p.price, product.currencyCode)} · ${scheduledTime(p.time, timezone)}${p.failureCode != null ? ' · ${OrdersStrings.priceFailed}' : ''}')
            .join('\n');
    return Tooltip(
        message: tooltip,
        child: TextButton(
            focusNode: focusNode,
            onPressed: onOpen,
            style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.centerLeft),
            child: Semantics(
                label: '${product.title}: $summary',
                excludeSemantics: true,
                child: Row(children: [
                  Icon(plans.isEmpty ? Icons.add : Icons.schedule, size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(summary,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                ]))));
  }
}
