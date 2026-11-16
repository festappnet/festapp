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
    this.onConfigure,
  });
  final OrderPaymentActions actions;
  final VoidCallback? onPair, onConfigure;
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
      if (actions.showBankSetup) ...[
        Text(PaymentMethodStrings.text('bankSetupRequired')),
        if (actions.canConfigureBank)
          TextButton(
            onPressed: onConfigure,
            child: Text(PaymentMethodStrings.text('configureBank')),
          ),
      ],
      if (actions.showBankAccess)
        Text(PaymentMethodStrings.text('bankAccessRequired')),
    ],
  );
}
