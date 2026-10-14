import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_sync_warning.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// A keyboard and touch accessible explanation alongside the unchanged status.
class BankSyncWarningButton extends StatelessWidget {
  final BankSyncWarning warning;
  final bool showPaymentHelp;
  const BankSyncWarningButton(
      {super.key, required this.warning, this.showPaymentHelp = true});

  @override
  Widget build(BuildContext context) {
    final reason = OrdersStrings.bankSyncWarningReason(warning.code);
    return IconButton(
      tooltip: [
        OrdersStrings.bankSyncWarningTitle,
        if (warning.bankAccountTitle.isNotEmpty) warning.bankAccountTitle,
        reason,
        if (showPaymentHelp) OrdersStrings.bankSyncWarningHelp,
        warning.contacts.isEmpty
            ? OrdersStrings.bankSyncWarningFallback
            : OrdersStrings.bankSyncWarningContact,
        for (final contact in warning.contacts)
          [contact.name, if (contact.email?.isNotEmpty == true) contact.email!]
              .where((part) => part.isNotEmpty)
              .join(' - '),
      ].join('\n'),
      icon: const Icon(Icons.warning_amber_rounded),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.amber.shade200
          : Colors.brown.shade800,
      iconSize: 22,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      onPressed: () => showDialog<void>(
        context: context,
        builder: (context) => AppAlertDialog(
          scrollable: true,
          title: Text(OrdersStrings.bankSyncWarningTitle),
          content: SelectionArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (warning.bankAccountTitle.isNotEmpty) ...[
                  Text(
                    warning.bankAccountTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                Text(reason),
                if (showPaymentHelp) ...[
                  const SizedBox(height: 12),
                  Text(OrdersStrings.bankSyncWarningHelp),
                ],
                const SizedBox(height: 16),
                Text(
                  warning.contacts.isEmpty
                      ? OrdersStrings.bankSyncWarningFallback
                      : OrdersStrings.bankSyncWarningContact,
                ),
                for (final contact in warning.contacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      [
                        contact.name,
                        if (contact.email?.isNotEmpty == true) contact.email!,
                      ].where((part) => part.isNotEmpty).join('\n'),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(CommonStrings.close),
            ),
          ],
        ),
      ),
    );
  }
}
