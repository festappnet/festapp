import 'package:flutter/material.dart';
import '../../features/ticket_feature.dart';
import '../ticket_delivery_strings.dart';

/// One event-wide setting. Choosing a format never enables ticket issuance.
class TicketDeliverySelector extends StatelessWidget {
  const TicketDeliverySelector(
      {super.key,
      required this.value,
      required this.enabled,
      required this.onChanged});
  final TicketDeliveryMode value;
  final bool enabled;
  final ValueChanged<TicketDeliveryMode> onChanged;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(TicketDeliveryStrings.text('title'),
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(TicketDeliveryStrings.text('scopeHelp')),
        for (final mode in TicketDeliveryMode.values)
          RadioListTile<TicketDeliveryMode>(
              contentPadding: EdgeInsets.zero,
              value: mode,
              groupValue: value,
              title: Text(TicketDeliveryStrings.label(mode)),
              subtitle: Text(TicketDeliveryStrings.description(mode)),
              onChanged: enabled ? (next) => onChanged(next!) : null),
        if (value != TicketDeliveryMode.pdfAttachment) ...[
          const SizedBox(height: 8),
          Text(TicketDeliveryStrings.text('reviewTemplate')),
        ],
        if (value == TicketDeliveryMode.both)
          Text(TicketDeliveryStrings.text('sameTicket')),
      ]);
}
