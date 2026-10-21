import 'package:fstapp/data_services/authorization_capabilities.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/_shared/drag_handle_dots.dart';
import 'package:festapp_core/eshop.dart';

import '../bank_account_strings.dart';
import 'bank_account_sync_status.dart';

class UnitBankAccountCard extends StatelessWidget {
  final BankAccountModel account;
  final Set<String> primaryCurrencies;
  final int index;
  final VoidCallback? onOpen;
  final VoidCallback? onUnlink;
  final Widget? selection;
  final bool showSyncHelp;

  const UnitBankAccountCard({
    super.key,
    required this.account,
    required this.primaryCurrencies,
    required this.index,
    this.onOpen,
    this.onUnlink,
    this.selection,
    this.showSyncHelp = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selection != null) selection!,
        if (onOpen != null)
          IconButton(
            tooltip: RightsService.hasBankCapability(
                    account.id, AuthorizationCapabilities.bankAccountsWrite)
                ? CommonStrings.edit
                : BankAccountStrings.bankAccountSettingsTitle,
            icon: Icon(
              RightsService.hasBankCapability(
                      account.id, AuthorizationCapabilities.bankAccountsWrite)
                  ? Icons.edit_outlined
                  : Icons.visibility_outlined,
            ),
            onPressed: onOpen,
          ),
        if (onUnlink != null)
          IconButton(
            tooltip: BankAccountStrings.unlink,
            icon: const Icon(Icons.link_off),
            onPressed: onUnlink,
          ),
        if (selection == null &&
            RightsService.hasCapability(
                AuthorizationCapabilities.bankAccountsUnitManage))
          ReorderableDragStartListener(
            index: index,
            child: const SizedBox(
              width: 40,
              height: 40,
              child: DragHandleDots(),
            ),
          ),
      ],
    );
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          account.title ?? BankAccountStrings.untitled,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if ((account.accountNumberHumanReadable ?? account.accountNumber)
            case final number?) ...[
          const SizedBox(height: 4),
          Text(number, style: Theme.of(context).textTheme.bodyMedium),
        ],
        BankAccountSyncStatus(account: account, showHelp: showSyncHelp),
        if (account.supportedCurrencies.isNotEmpty) ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final currency in account.supportedCurrencies)
                Tooltip(
                  message: primaryCurrencies.contains(currency)
                      ? BankAccountStrings.primaryAccountFor(currency)
                      : BankAccountStrings.backupAccountFor(currency),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: primaryCurrencies.contains(currency)
                          ? colors.primaryContainer
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          currency,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: primaryCurrencies.contains(currency)
                                ? colors.onPrimaryContainer
                                : colors.onSurfaceVariant,
                          ),
                        ),
                        if (primaryCurrencies.contains(currency)) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.star,
                            size: 12,
                            color: colors.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 420) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  details,
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: details),
                const SizedBox(width: 12),
                actions,
              ],
            );
          },
        ),
      ),
    );
  }
}
