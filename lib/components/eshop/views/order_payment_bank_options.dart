import 'package:material_ui/material_ui.dart';

import '../models/order_payment_actions.dart';
import '../orders_strings.dart';
import '../../forms/payment_method_strings.dart';

/// Displays the server's permitted actions without probing bank data.
class OrderPaymentBankOptions extends StatelessWidget {
  const OrderPaymentBankOptions({
    super.key,
    required this.actions,
    this.onPair,
    this.onHistory,
    this.onConfigure,
  });
  final OrderPaymentActions actions;
  final VoidCallback? onPair, onConfigure;
  final ValueChanged<PaymentHistoryAccount>? onHistory;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (actions.pairingAccountId != null)
        TextButton.icon(
          onPressed: onPair,
          icon: const Icon(Icons.account_balance),
          label: Text(OrdersStrings.findAndLinkTransaction),
        ),
      for (final account in actions.historyAccounts)
        TextButton.icon(
          onPressed: onHistory == null ? null : () => onHistory!(account),
          icon: const Icon(Icons.history),
          label: Text(
            '${PaymentMethodStrings.text('bankHistory')}: ${account.title}',
          ),
        ),
      if (actions.bankState == 'absent' && actions.historyAccounts.isEmpty) ...[
        Text(PaymentMethodStrings.text('bankSetupRequired')),
        if (actions.canConfigureBank)
          TextButton(
            onPressed: onConfigure,
            child: Text(PaymentMethodStrings.text('configureBank')),
          ),
      ],
      if (actions.bankState == 'restricted' ||
          (actions.bankState == 'configured' &&
              actions.pairingAccountId == null &&
              actions.historyAccounts.isEmpty))
        Text(PaymentMethodStrings.text('bankAccessRequired')),
    ],
  );
}
