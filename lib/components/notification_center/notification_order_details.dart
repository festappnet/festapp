import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'notification_center_strings.dart';

/// Notes stay in the expanded item; ticket symbols are visible before opening
/// their individual notes, and long batches do not overwhelm the notification.
class NotificationOrderDetails extends StatelessWidget {
  const NotificationOrderDetails(
      {super.key, required this.load, required this.onRetry});
  final Future<Map<String, dynamic>?> load;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>?>(
        future: load,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 16),
                label:
                    Text(NotificationCenterStrings.text('detailUnavailable')));
          }
          if (snapshot.connectionState != ConnectionState.done) {
            return const Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 2));
          }
          final details = snapshot.data;
          if (details == null) return const SizedBox.shrink();
          final order = details['order'] as Map;
          final data = order['data'] as Map? ?? const {};
          final tickets = details['tickets'] as List? ?? const [];
          Widget? note(dynamic text, String label) {
            final value = text?.toString().trim() ?? '';
            return value.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('$label: $value',
                        style: Theme.of(context).textTheme.bodyMedium));
          }

          String ticketSymbol(dynamic ticket) =>
              '#${ticket['ticket_symbol'] ?? ticket['id']}';
          final notes = [
            note(data['note'], CommonStrings.note),
            note(order['note_hidden'], OrdersStrings.gridHiddenNote),
          ].whereType<Widget>();
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...notes,
                if (tickets.isNotEmpty)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(left: 12, bottom: 8),
                    title: Text('${OrdersStrings.tickets} (${tickets.length})',
                        style: Theme.of(context).textTheme.bodyMedium),
                    subtitle: Text(
                        '${tickets.take(3).map(ticketSymbol).join(' · ')}${tickets.length > 3 ? ' …' : ''}',
                        style: Theme.of(context).textTheme.bodySmall),
                    children: [
                      for (final ticket in tickets)
                        Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(ticketSymbol(ticket),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall),
                                  if (note(ticket['note'], CommonStrings.note)
                                      case final widget?)
                                    widget,
                                  if (note(ticket['note_hidden'],
                                          OrdersStrings.gridHiddenNote)
                                      case final widget?)
                                    widget,
                                ])),
                    ],
                  ),
              ]);
        },
      );
}
