import 'package:material_ui/material_ui.dart';

import '../ticket_delivery_strings.dart';

/// Independent of delivery format; preference remains editable before activation.
class TicketWalletSelector extends StatelessWidget {
  const TicketWalletSelector({
    super.key,
    required this.value,
    required this.enabled,
    required this.onChanged,
    this.ready = false,
  });
  final bool value;
  final bool enabled;
  final bool ready;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: value,
            onChanged: enabled ? (next) => onChanged(next ?? true) : null,
            title: Text(TicketDeliveryStrings.text('walletTitle')),
            subtitle: Text(TicketDeliveryStrings.text('walletHelp')),
          ),
          Text(
            TicketDeliveryStrings.text('walletFuture'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (!ready)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                TicketDeliveryStrings.text('walletUnavailable'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
        ],
      ),
    ),
  );
}
