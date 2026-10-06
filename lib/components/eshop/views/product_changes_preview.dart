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

  List<Widget> _tickets(BuildContext context, List<OrderTicketChange> tickets,
          Color color, String status,
          {bool cancelled = false, String prefix = ''}) =>
      [
        for (final ticket in tickets) ...[
          _ticketHeading(ticket,
              status: status, color: color, cancelled: cancelled),
          for (final product in ticket.products)
            _product(context, product, prefix: prefix, color: color),
          const SizedBox(height: 12),
        ],
      ];

  Widget _ticketHeading(OrderTicketChange ticket,
          {String? status, Color? color, bool cancelled = false}) =>
      Wrap(spacing: 8, runSpacing: 4, children: [
        Text(OrdersStrings.changeTicketLabel(_symbol(ticket)),
            style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                decoration: cancelled ? TextDecoration.lineThrough : null)),
        if (status != null) Text('($status)', style: TextStyle(color: color)),
      ]);

  Widget _transition(
      BuildContext context, String label, String before, String after,
      {bool total = false}) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(left: total ? 0 : 8, top: 4),
      child: Wrap(
          spacing: 12,
          runSpacing: 4,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(total ? label : '• $label:',
                style: total
                    ? const TextStyle(fontWeight: FontWeight.bold)
                    : null),
            Text.rich(
                TextSpan(style: DefaultTextStyle.of(context).style, children: [
              TextSpan(
                  text: before,
                  style: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: theme.textTheme.bodySmall?.color)),
              WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(Icons.arrow_forward,
                          size: 16, color: theme.colorScheme.primary))),
              TextSpan(
                  text: after,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ])),
          ]),
    );
  }

  String _price(BuildContext context, ProductModel product) =>
      Utilities.formatPrice(context, product.price ?? 0,
          currencyCode: product.currencyCode ?? changes.currencyCode);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.list_alt_outlined,
                size: 18, color: theme.textTheme.bodySmall?.color)),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(OrdersStrings.orderChangesOverview),
          const SizedBox(height: 8),
          if (!changes.hasChanges)
            Text(OrdersStrings.noProductChangesDetected,
                style: TextStyle(
                    fontStyle: FontStyle.italic,
                    color: theme.textTheme.bodySmall?.color))
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._tickets(context, changes.cancelledTickets, Colors.red,
                        OrdersStrings.cancelledTicketStatus,
                        cancelled: true, prefix: '- '),
                    ..._tickets(context, changes.removedTickets, Colors.red,
                        OrdersStrings.removedTicketStatus,
                        prefix: '- '),
                    ..._tickets(context, changes.addedTickets, Colors.green,
                        OrdersStrings.addedTicketStatus,
                        prefix: '+ '),
                    for (final ticket in changes.productChanges) ...[
                      _ticketHeading(ticket),
                      for (final product in ticket.added)
                        _product(context, product,
                            prefix: '+ ', color: Colors.green),
                      for (final product in ticket.removed)
                        _product(context, product,
                            prefix: '- ', color: Colors.red),
                      for (final product in ticket.changed) ...[
                        if (product.from.title != product.to.title)
                          _transition(context, product.to.title ?? '',
                              product.from.title ?? '', product.to.title ?? ''),
                        if (product.from.price != product.to.price ||
                            product.from.currencyCode !=
                                product.to.currencyCode)
                          _transition(
                              context,
                              product.to.title ?? '',
                              _price(context, product.from),
                              _price(context, product.to)),
                      ],
                      const SizedBox(height: 12),
                    ],
                    if (changes.referenceTotal != changes.currentTotal) ...[
                      const Divider(height: 16),
                      _transition(
                          context,
                          OrdersStrings.totalPriceChange,
                          Utilities.formatPrice(context, changes.referenceTotal,
                              currencyCode: changes.currencyCode),
                          Utilities.formatPrice(context, changes.currentTotal,
                              currencyCode: changes.currencyCode),
                          total: true),
                    ],
                  ]),
            ),
        ])),
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
