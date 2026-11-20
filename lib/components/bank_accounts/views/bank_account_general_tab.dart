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
  final TextEditingController bankCodeController;

  final bool useIbanInput;
  final ValueChanged<bool> onUseIbanInputChanged;

  final FormFieldValidator<String> validateIban;
  final FormFieldValidator<String> validateAccountNumber;
  final FormFieldValidator<String> validateBankCode;

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
    required this.bankCodeController,
    required this.useIbanInput,
    required this.onUseIbanInputChanged,
    required this.validateIban,
    required this.validateAccountNumber,
    required this.validateBankCode,
    required this.supportedCurrencies,
    required this.onAddCurrency,
    required this.onRemoveCurrency,
    required this.onSave,
    required this.onIbanChanged,
    required this.onNationalAccountChanged,
  });

  static final _pastedAccount = RegExp(r'^([^/]+)\s*/\s*(\d{4})$');

  void _onAccountNumberChanged(String value) {
    final pasted = _pastedAccount.firstMatch(value.trim());
    if (pasted != null) {
      final number = pasted[1]!.trim();
      nationalAccountController.value = TextEditingValue(
        text: number,
        selection: TextSelection.collapsed(offset: number.length),
      );
      bankCodeController.text = pasted[2]!;
    }
    onNationalAccountChanged();
  }

  Widget _nationalAccountFields(BuildContext context) {
    final theme = Theme.of(context);
    final bankCode = bankCodeController.text.trim();
    final bankName = czBanks[bankCode];

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: TextFormField(
                      key: const ValueKey('bank-account-national'),
                      controller: nationalAccountController,
                      decoration: InputDecoration(
                        labelText: BankAccountStrings.accountNumberLabel,
                        hintText: isReadOnly ? null : '20001457',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        errorMaxLines: 3,
                      ),
                      readOnly: isReadOnly,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: _onAccountNumberChanged,
                      validator: validateAccountNumber,
                      autovalidateMode:
                          AutovalidateMode.onUserInteractionIfError,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: ExcludeSemantics(
                      child: Text(
                        '/',
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: (constraints.maxWidth * .43).clamp(96.0, 136.0),
                    child: TextFormField(
                      key: const ValueKey('bank-account-bank-code'),
                      controller: bankCodeController,
                      decoration: InputDecoration(
                        labelText: BankAccountStrings.bankCodeLabel,
                        hintText: isReadOnly ? null : '0800',
                        floatingLabelBehavior: FloatingLabelBehavior.always,
                        errorMaxLines: 3,
                        suffixIcon: isReadOnly
                            ? null
                            : PopupMenuButton<String>(
                                tooltip: BankAccountStrings.bankCodeLabel,
                                icon: const Icon(Icons.arrow_drop_down),
                                initialValue: bankName == null
                                    ? null
                                    : bankCode,
                                onSelected: (code) {
                                  bankCodeController.text = code;
                                  onNationalAccountChanged();
                                },
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
                      keyboardType: TextInputType.number,
                      readOnly: isReadOnly,
                      onChanged: (_) => onNationalAccountChanged(),
                      validator: validateBankCode,
                      autovalidateMode:
                          AutovalidateMode.onUserInteractionIfError,
                    ),
                  ),
                ],
              ),
              if (bankName != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    bankName,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
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
                  validator: validateIban,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                )
              else
                _nationalAccountFields(context),
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
