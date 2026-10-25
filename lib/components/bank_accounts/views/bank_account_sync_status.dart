import 'package:material_ui/material_ui.dart';
import '../bank_account_strings.dart';
import 'package:festapp_core/eshop.dart';
import '../../eshop/orders_strings.dart';
import 'bank_sync_warning_button.dart';

/// Safe operational status, including for viewers without account admin rights.
class BankAccountSyncStatus extends StatelessWidget {
  final BankAccountModel account;
  final bool showHelp;
  const BankAccountSyncStatus(
      {super.key, required this.account, this.showHelp = true});

  @override
  Widget build(BuildContext context) {
    if (account.type.toUpperCase() == 'CASH') return const SizedBox.shrink();
    final state = account.bankSync?.state;
    final warning = account.bankSyncWarning ??
        (state == 'connected'
            ? null
            : BankSyncWarning(
                code: switch (state) {
                  'suspended' => 'suspended',
                  'degraded' => 'bank_error',
                  _ => 'not_configured',
                },
                bankAccountTitle:
                    account.title ?? BankAccountStrings.bankAccount,
              ));
    return Row(
      children: [
        if (warning != null && showHelp)
          BankSyncWarningButton(warning: warning, showPaymentHelp: false)
        else
          Padding(
            padding: EdgeInsets.all(8),
            child: Icon(
                warning == null
                    ? Icons.check_circle_outline
                    : Icons.info_outline,
                size: 20),
          ),
        Flexible(
          child: Text(
            warning == null
                ? BankAccountStrings.connectionStatus('connected')
                : OrdersStrings.bankSyncWarningReason(warning.code),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
