import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:festapp_core/eshop.dart';

import '../models/form_editor_draft.dart';
import '../../bank_accounts/bank_account_strings.dart';

/// The editor RPC supplies only accounts linked to the form's unit, in SQL
/// priority/id order. Management access is separate from form authoring access.
class FormBankAccountPicker extends StatelessWidget {
  const FormBankAccountPicker({
    super.key,
    required this.form,
    required this.currencies,
    required this.canEdit,
    required this.onChanged,
  });

  final FormEditorDraft form;
  final Set<String> currencies;
  final bool canEdit;
  final VoidCallback onChanged;

  String _label(BankAccountModel account) {
    final label =
        [
              account.title,
              account.accountNumberHumanReadable ?? account.accountNumber,
            ]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(' — ');
    return label.isEmpty ? 'ID ${account.id}' : label;
  }

  @override
  Widget build(BuildContext context) {
    // FormEditBundle supplies a known list, including when it is empty.
    final accounts = form.availableBankAccounts ?? const <BankAccountModel>[];
    final selected = form.definition.bankAccountId;
    final eligible = accounts
        .where(
          (a) =>
              a.type != 'CASH' &&
              currencies.every((c) => a.supportedCurrencies.contains(c.trim())),
        )
        .toList();
    final unavailable =
        selected != null && !eligible.any((a) => a.id == selected);
    final selectedAccount = accounts.firstWhereOrNull((a) => a.id == selected);
    // String values give the inherited NULL option a concrete dropdown value.
    final labels = <String, String>{
      'default': BankAccountStrings.formAccountDefaultPlain,
      for (final account in eligible) account.id.toString(): _label(account),
      if (unavailable)
        selected.toString(): BankAccountStrings.formAccountUnavailable(
          selectedAccount == null ? 'ID $selected' : _label(selectedAccount),
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selected?.toString() ?? 'default',
          isDense: false,
          isExpanded: true,
          itemHeight: null,
          decoration: InputDecoration(
            labelText: BankAccountStrings.formAccountLabel,
            border: const OutlineInputBorder(),
          ),
          selectedItemBuilder: (context) => [
            for (final label in labels.values)
              Tooltip(
                message: label,
                child: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ],
          items: [
            for (final entry in labels.entries)
              DropdownMenuItem(
                value: entry.key,
                enabled: !unavailable || entry.key != selected.toString(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(entry.value),
                ),
              ),
          ],
          onChanged: !canEdit
              ? null
              : (value) {
                  if (value == null) return;
                  final id = value == 'default' ? null : int.parse(value);
                  form.definition = form.definition.copyWith(bankAccountId: id);
                  form.bankAccount = id == null
                      ? null
                      : eligible.firstWhere((a) => a.id == id);
                  onChanged();
                },
        ),
        if (unavailable) ...[
          const SizedBox(height: 4),
          Text(BankAccountStrings.formAccountUnavailableHelp),
        ],
      ],
    );
  }
}

/// Match bank_payment_provider_internal's visible, paid product currency set.
Set<String> formBankTransferCurrencies(FormEditorDraft form) {
  final currencies = <String>{};
  for (final field in form.relatedFields) {
    if (field.definition.isHidden == true) continue;
    for (final product
        in field.definition.productType?.products ?? <ProductModel>[]) {
      if (product.isHidden == true || (product.price ?? 0) <= 0) continue;
      final currency = product.currencyCode?.trim();
      if (currency != null && currency.isNotEmpty) currencies.add(currency);
    }
  }
  return currencies;
}

/// The editor RPC returns non-cash accounts in the same priority and ID order
/// used when checkout resolves an inherited receiving account.
Map<String, BankAccountModel?> formBankTransferAccounts(
  FormEditorDraft form,
  Set<String> currencies, {
  int? accountId,
}) {
  final accounts = form.availableBankAccounts ?? const <BankAccountModel>[];
  return {
    for (final currency in currencies.toList()..sort())
      currency: accounts.firstWhereOrNull(
        (account) =>
            account.type != 'CASH' &&
            (accountId == null || account.id == accountId) &&
            account.supportedCurrencies.contains(currency),
      ),
  };
}
