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
  Widget build(BuildContext context) => Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            DropdownButtonFormField<TicketDeliveryMode>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(
                  labelText: TicketDeliveryStrings.text('title'),
                  border: const OutlineInputBorder(),
                  isDense: true),
              items: [
                for (final mode in TicketDeliveryMode.values)
                  DropdownMenuItem(
                      value: mode,
                      child: Text(TicketDeliveryStrings.label(mode))),
              ],
              onChanged: enabled ? (next) => onChanged(next!) : null,
            ),
            const SizedBox(height: 8),
            Text(TicketDeliveryStrings.description(value),
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
