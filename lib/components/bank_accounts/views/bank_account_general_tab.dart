import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/components/bank_accounts/data/cz_banks.dart';

class BankAccountGeneralTab extends StatefulWidget {
  final bool isReadOnly;
  final bool isSaving;
  final GlobalKey<FormState> formKey;

  final TextEditingController titleController;
  final TextEditingController creditorNameController;
  final TextEditingController ibanController;
  final TextEditingController prefixController;
  final TextEditingController accountBodyController;

  final bool useIbanInput;
  final ValueChanged<bool> onUseIbanInputChanged;

  final String? selectedBankCode;
  final ValueChanged<String?> onSelectedBankCodeChanged;

  final String? ibanError;

  final List<String> supportedCurrencies;
  final VoidCallback onAddCurrency;
  final ValueChanged<String> onRemoveCurrency;

  final String? Function() buildLegacyHumanReadable;
  final VoidCallback onSave;
  final VoidCallback onIbanChanged;
  final VoidCallback onHumanChanged;

  const BankAccountGeneralTab({
    super.key,
    required this.isReadOnly,
    required this.isSaving,
    required this.formKey,
    required this.titleController,
    required this.creditorNameController,
    required this.ibanController,
    required this.prefixController,
    required this.accountBodyController,
    required this.useIbanInput,
    required this.onUseIbanInputChanged,
    required this.selectedBankCode,
    required this.onSelectedBankCodeChanged,
    required this.ibanError,
    required this.supportedCurrencies,
    required this.onAddCurrency,
    required this.onRemoveCurrency,
    required this.buildLegacyHumanReadable,
    required this.onSave,
    required this.onIbanChanged,
    required this.onHumanChanged,
  });

  @override
  State<BankAccountGeneralTab> createState() => _BankAccountGeneralTabState();
}

class _BankAccountGeneralTabState extends State<BankAccountGeneralTab> {
  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: widget.formKey,
          child: Column(
            children: [
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.titleController,
                decoration: InputDecoration(
                  labelText: BankAccountStrings.titleLabel,
                ),
                readOnly: widget.isReadOnly,
                validator: (v) =>
                    v!.isEmpty ? CommonStrings.fieldCannotBeEmpty : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: widget.creditorNameController,
                decoration: InputDecoration(
                  labelText: BankAccountStrings.creditorNameLabel,
                  helperText: BankAccountStrings.creditorNameHelp,
                ),
                readOnly: widget.isReadOnly,
                maxLength: 70,
              ),
              const SizedBox(height: 16),
              const SizedBox(height: 24),
              if (!widget.isReadOnly)
                LayoutBuilder(
                  builder: (context, constraints) {
                    return ToggleButtons(
                      isSelected: [!widget.useIbanInput, widget.useIbanInput],
                      onPressed: (index) =>
                          widget.onUseIbanInputChanged(index == 1),
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
              if (widget.useIbanInput)
                TextFormField(
                  controller: widget.ibanController,
                  decoration: InputDecoration(
                    labelText: BankAccountStrings.accountNumberLabel,
                    errorText: widget.ibanError,
                    helperText: widget.useIbanInput && !widget.isReadOnly
                        ? BankAccountStrings.ibanValidationHelp
                        : null,
                  ),
                  readOnly: widget.isReadOnly,
                  onChanged: (_) => widget.onIbanChanged(),
                  validator: (v) =>
                      v!.isEmpty ? CommonStrings.fieldCannotBeEmpty : null,
                )
              else
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: widget.prefixController,
                              decoration: InputDecoration(
                                labelText: BankAccountStrings.prefixLabel,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) => widget.onHumanChanged(),
                              readOnly: widget.isReadOnly,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: widget.accountBodyController,
                              decoration: InputDecoration(
                                labelText:
                                    BankAccountStrings.accountNumberLabel,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (_) => widget.onHumanChanged(),
                              readOnly: widget.isReadOnly,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: czBanks.containsKey(widget.selectedBankCode)
                            ? widget.selectedBankCode
                            : null,
                        decoration: InputDecoration(
                          labelText: BankAccountStrings.bankCodeLabel,
                        ),
                        items: czBanks.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  "${e.value} (${e.key})",
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: widget.isReadOnly
                            ? null
                            : (v) {
                                widget.onSelectedBankCodeChanged(v);
                                widget.onHumanChanged();
                              },
                      ),
                      if (widget.selectedBankCode != null &&
                          widget.accountBodyController.text.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            "${BankAccountStrings.fullFormatLabel} ${widget.buildLegacyHumanReadable() ?? ''}",
                            style: TextStyle(
                              color: Theme.of(context).hintColor,
                              fontSize: 13,
                            ),
                          ),
                        ),
                    ],
                  ),
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
                        ...widget.supportedCurrencies.map(
                          (c) => Chip(
                            label: Text(c),
                            onDeleted: widget.isReadOnly
                                ? null
                                : () => widget.onRemoveCurrency(c),
                          ),
                        ),
                        if (!widget.isReadOnly)
                          ActionChip(
                            avatar: const Icon(Icons.add, size: 16),
                            label: Text(BankAccountStrings.addCurrency),
                            onPressed: widget.onAddCurrency,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              if (!widget.isReadOnly)
                ElevatedButton(
                  onPressed: widget.isSaving ? null : widget.onSave,
                  child: widget.isSaving
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
