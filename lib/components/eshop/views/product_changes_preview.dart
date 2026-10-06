import 'package:flutter/material.dart';
import '../models/order_change_summary.dart';
import '../models/product_model.dart';
import '../orders_strings.dart';
import 'package:fstapp/services/utilities_all.dart';

class ProductChangesPreview extends StatelessWidget {
  final OrderChangeSummary changes;
  const ProductChangesPreview({super.key, required this.changes});

  String _symbol(OrderTicketChange ticket) =>
      ticket.ticketSymbol ?? OrdersStrings.ticketWithoutSymbol;

  Widget _product(BuildContext context, ProductModel product,
          {String prefix = '', Color? color}) =>
      Padding(
        padding: const EdgeInsets.only(left: 8, top: 4),
        child: Text(
            '$prefix${product.title ?? ""} (${Utilities.formatPrice(context, product.price ?? 0, currencyCode: product.currencyCode ?? changes.currencyCode)})',
            style: TextStyle(color: color)),
      );

  List<Widget> _tickets(BuildContext context, String title,
          List<OrderTicketChange> tickets, Color color) =>
      tickets.isEmpty
          ? []
          : [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
              for (final ticket in tickets) ...[
                Text(OrdersStrings.changeTicketLabel(_symbol(ticket)),
                    style:
                        TextStyle(color: color, fontWeight: FontWeight.w600)),
                for (final product in ticket.products)
                  _product(context, product),
                const SizedBox(height: 8),
              ],
            ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(OrdersStrings.orderChangesOverview),
        const SizedBox(height: 8),
        if (!changes.hasChanges)
          Text(OrdersStrings.noProductChangesDetected)
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade200)),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ..._tickets(context, OrdersStrings.cancelledTicketsTitle,
                  changes.cancelledTickets, Colors.red),
              ..._tickets(context, OrdersStrings.removedTicketsTitle,
                  changes.removedTickets, Colors.red),
              ..._tickets(context, OrdersStrings.addedTicketsTitle,
                  changes.addedTickets, Colors.green),
              for (final ticket in changes.productChanges) ...[
                Text(OrdersStrings.productChangesForTicket(_symbol(ticket)),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (ticket.added.isNotEmpty) ...[
                  Text(OrdersStrings.addedProductsTitle),
                  for (final product in ticket.added)
                    _product(context, product,
                        prefix: '+ ', color: Colors.green),
                ],
                if (ticket.removed.isNotEmpty) ...[
                  Text(OrdersStrings.removedProductsTitle),
                  for (final product in ticket.removed)
                    _product(context, product, prefix: '- ', color: Colors.red),
                ],
                for (final product in ticket.changed)
                  Padding(
                      padding: const EdgeInsets.only(left: 8, top: 4),
                      child: Text(
                          '${product.from.title ?? ""} (${Utilities.formatPrice(context, product.from.price ?? 0, currencyCode: changes.currencyCode)}) → ${product.to.title ?? ""} (${Utilities.formatPrice(context, product.to.price ?? 0, currencyCode: changes.currencyCode)})')),
                const SizedBox(height: 8),
              ],
              if (changes.referenceTotal != changes.currentTotal) ...[
                const Divider(height: 16),
                Wrap(spacing: 16, runSpacing: 4, children: [
                  Text(OrdersStrings.totalPriceChange,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                      '${Utilities.formatPrice(context, changes.referenceTotal, currencyCode: changes.currencyCode)} → ${Utilities.formatPrice(context, changes.currentTotal, currencyCode: changes.currencyCode)}',
                      style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary)),
                ]),
              ],
            ]),
          ),
      ]),
    );
  }

  static Widget buildConfirmationListItem(
          BuildContext context, IconData icon, String text) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon,
              size: 18, color: Theme.of(context).textTheme.bodySmall?.color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ]),
      );
}
