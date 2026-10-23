import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:url_launcher/link.dart';
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
    final canManage = RightsService.hasBankCapability(
            warning.bankAccountId, AuthorizationCapabilities.bankSyncManage) &&
        warning.bankAccountId != null;
    final guidance = warning.code == 'suspended'
        ? OrdersStrings.bankSyncWarningEnable
        : OrdersStrings.bankSyncWarningManage;
    Widget settingsLink({VoidCallback? beforeOpen}) => Link(
          uri: Uri(path: '/bank-accounts/${warning.bankAccountId}/connection'),
          target: LinkTarget.self,
          builder: (context, followLink) => TextButton(
            onPressed: followLink == null
                ? null
                : () async {
                    beforeOpen?.call();
                    Tooltip.dismissAllToolTips();
                    await followLink();
                  },
            child: Text(OrdersStrings.bankSyncWarningOpenSettings,
                style: const TextStyle(decoration: TextDecoration.underline)),
          ),
        );
    final reason = showPaymentHelp && warning.code == 'suspended'
        ? OrdersStrings.bankSyncPaymentPaused
        : OrdersStrings.bankSyncWarningReason(warning.code);
    final button = IconButton(
      tooltip: canManage
          ? null
          : [
              '$reason (${OrdersStrings.bankSyncWarningDetailsHint})',
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
                if (canManage) ...[
                  SelectableText(guidance),
                  settingsLink(beforeOpen: () => Navigator.of(context).pop()),
                ] else ...[
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
    if (!canManage) return button;
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      richMessage: TextSpan(children: [
        TextSpan(
            text: '$reason (${OrdersStrings.bankSyncWarningDetailsHint})\n$guidance\n'),
        WidgetSpan(child: settingsLink()),
      ]),
      ignorePointer: false,
      waitDuration: const Duration(milliseconds: 350),
      exitDuration: const Duration(milliseconds: 500),
      showDuration: const Duration(seconds: 10),
      constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 32).clamp(0.0, 360.0)),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(12),
      textStyle: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: colors.onSurface, height: 1.4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: button,
    );
  }
}
