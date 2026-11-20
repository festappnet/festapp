import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:festapp_core/eshop.dart';

class BankAccountGeneralTab extends StatelessWidget {
  final bool isReadOnly;
  final bool isSaving;
  final GlobalKey<FormState> formKey;

  final TextEditingController titleController;
  final TextEditingController creditorNameController;
  final TextEditingController ibanController;
  final TextEditingController nationalAccountController;

  final bool useIbanInput;
  final ValueChanged<bool> onUseIbanInputChanged;

  final String? selectedBankCode;
  final FormFieldValidator<String> validateAccountNumber;

  final List<String> supportedCurrencies;
  final VoidCallback onAddCurrency;
  final ValueChanged<String> onRemoveCurrency;

  final VoidCallback onSave;
  final VoidCallback onIbanChanged;
  final VoidCallback onNationalAccountChanged;

  const BankAccountGeneralTab({
    super.key,
    required this.isReadOnly,
    required this.isSaving,
    required this.formKey,
    required this.titleController,
    required this.creditorNameController,
    required this.ibanController,
    required this.nationalAccountController,
    required this.useIbanInput,
    required this.onUseIbanInputChanged,
    required this.selectedBankCode,
    required this.validateAccountNumber,
    required this.supportedCurrencies,
    required this.onAddCurrency,
    required this.onRemoveCurrency,
    required this.onSave,
    required this.onIbanChanged,
    required this.onNationalAccountChanged,
  });

  void _selectBank(String code) {
    final account = nationalAccountController.text.split('/').first.trim();
    final text = '$account/$code';
    nationalAccountController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: account.length),
    );
    onNationalAccountChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: formKey,
          child: Column(
            children: [
              const SizedBox(height: 16),
              TextFormField(
                controller: titleController,
                maxLength: 120,
                decoration: InputDecoration(
                  labelText: BankAccountStrings.titleLabel,
                ),
                readOnly: isReadOnly,
                validator: (v) =>
                    v!.isEmpty ? CommonStrings.fieldCannotBeEmpty : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: creditorNameController,
                decoration: InputDecoration(
                  labelText: BankAccountStrings.creditorNameLabel,
                  helperText: BankAccountStrings.creditorNameHelp,
                ),
                readOnly: isReadOnly,
                maxLength: 70,
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 24),
              if (!isReadOnly)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ToggleButtons(
                      isSelected: [!useIbanInput, useIbanInput],
                      onPressed: (index) => onUseIbanInputChanged(index == 1),
                      borderRadius: BorderRadius.circular(8),
                      constraints: BoxConstraints.expand(
                        width: (constraints.maxWidth - 4) / 2,
                        height: 40,
                      ),
                      children: [
                        Text(BankAccountStrings.inputModeSplit),
                        Text(BankAccountStrings.inputModeIban),
                      ],
                    );
                  },
                ),
              const SizedBox(height: 16),
              if (useIbanInput)
                TextFormField(
                  key: const ValueKey('bank-account-iban'),
                  controller: ibanController,
                  decoration: const InputDecoration(labelText: 'IBAN'),
                  readOnly: isReadOnly,
                  autocorrect: false,
                  onChanged: (_) => onIbanChanged(),
                  validator: validateAccountNumber,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                )
              else
                TextFormField(
                  key: const ValueKey('bank-account-national'),
                  controller: nationalAccountController,
                  decoration: InputDecoration(
                    labelText: BankAccountStrings.accountNumberLabel,
                    hintText: isReadOnly ? null : '20001457/0800',
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    helperText: czBanks[selectedBankCode],
                    helperMaxLines: 2,
                    errorMaxLines: 2,
                    suffixIcon: isReadOnly
                        ? null
                        : PopupMenuButton<String>(
                            tooltip: BankAccountStrings.bankCodeLabel,
                            icon: const Icon(Icons.arrow_drop_down),
                            initialValue: selectedBankCode,
                            onSelected: _selectBank,
                            itemBuilder: (context) => [
                              for (final bank in czBanks.entries)
                                PopupMenuItem(
                                  value: bank.key,
                                  child: Text(
                                    '${bank.key} · ${bank.value}',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  readOnly: isReadOnly,
                  autocorrect: false,
                  enableSuggestions: false,
                  onChanged: (_) => onNationalAccountChanged(),
                  validator: validateAccountNumber,
                  autovalidateMode: AutovalidateMode.onUserInteractionIfError,
                ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: BankAccountStrings.supportedCurrencies,
                  border: const OutlineInputBorder(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        ...supportedCurrencies.map(
                          (c) => Chip(
                            label: Text(c),
                            onDeleted: isReadOnly
                                ? null
                                : () => onRemoveCurrency(c),
                          ),
                        ),
                        if (!isReadOnly)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(BankAccountStrings.addCurrency),
                            onPressed: onAddCurrency,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!isReadOnly)
                ElevatedButton(
                  onPressed: isSaving ? null : onSave,
                  child: isSaving
                      ? const CircularProgressIndicator()
                      : Text(BankAccountStrings.saveChanges),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
