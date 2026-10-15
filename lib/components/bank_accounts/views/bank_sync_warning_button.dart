import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/copy_button.dart';
import 'package:festapp_core/eshop.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

/// A keyboard and touch accessible explanation alongside the unchanged status.
class BankSyncWarningButton extends StatelessWidget {
  final BankSyncWarning warning;
  final bool showPaymentHelp;
  final bool compact;
  const BankSyncWarningButton(
      {super.key,
      required this.warning,
      this.showPaymentHelp = true,
      this.compact = false});

  @override
  Widget build(BuildContext context) {
    final contacts = warning.uniqueContacts;
    final reason = showPaymentHelp && warning.code == 'suspended'
        ? OrdersStrings.bankSyncPaymentPaused
        : OrdersStrings.bankSyncWarningReason(warning.code);
    return IconButton(
      tooltip: [
        reason,
        contacts.isEmpty
            ? OrdersStrings.bankSyncWarningFallback
            : '${OrdersStrings.bankSyncWarningContactShort} ${contacts.map((contact) => contact.name.isNotEmpty ? contact.name : contact.email ?? '').join(', ')}',
      ].join('\n'),
      icon: const Icon(Icons.warning_amber_rounded),
      color: Theme.of(context).brightness == Brightness.dark
          ? Colors.amber.shade200
          : Colors.brown.shade800,
      iconSize: compact ? 20 : 22,
      padding: EdgeInsets.all(compact ? 2 : 4),
      constraints: BoxConstraints(
          minWidth: compact ? 24 : 40, minHeight: compact ? 24 : 40),
      style:
          IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
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
                  SelectableText(
                    warning.bankAccountTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                ],
                SelectableText(reason),
                if (showPaymentHelp) ...[
                  const SizedBox(height: 12),
                  SelectableText(OrdersStrings.bankSyncWarningHelp),
                ],
                const SizedBox(height: 16),
                SelectableText(
                  contacts.isEmpty
                      ? OrdersStrings.bankSyncWarningFallback
                      : OrdersStrings.bankSyncWarningContact,
                ),
                for (final contact in contacts)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (contact.name.isNotEmpty)
                          SelectableText(contact.name),
                        if (contact.email?.isNotEmpty == true)
                          Row(children: [
                            Flexible(child: SelectableText(contact.email!)),
                            const SizedBox(width: 8),
                            CopyButton(value: contact.email!),
                          ]),
                      ],
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
