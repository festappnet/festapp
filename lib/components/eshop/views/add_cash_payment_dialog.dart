import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/db_orders.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';

class AddCashPaymentDialog extends StatefulWidget {
  final int unitId;
  final String currency;
  final String variableSymbol;
  final int paymentInfoId;
  final bool isBankAdmin;

  const AddCashPaymentDialog({
    super.key,
    required this.unitId,
    required this.currency,
    required this.variableSymbol,
    required this.paymentInfoId,
    this.isBankAdmin = false,
  });

  @override
  State<AddCashPaymentDialog> createState() => _AddCashPaymentDialogState();
}

class _AddCashPaymentDialogState extends State<AddCashPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountController;
  late TextEditingController _noteController;
  DateTime _selectedDate = DateTime.now();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _amountController = TextEditingController(text: "0");
    _amountController.selection = TextSelection(
        baseOffset: 0, extentOffset: _amountController.text.length);
    _noteController = TextEditingController();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final double amount =
          double.parse(_amountController.text.replaceAll(',', '.'));

      await DbOrders.insertManualTransaction(
        amount: amount,
        currency: widget.currency,
        unitId: widget.unitId,
        variableSymbol: null,
        date: _selectedDate,
        note: _noteController.text.isEmpty ? null : _noteController.text,
        paymentInfoId: widget.paymentInfoId,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(OrdersStrings.addCashPaymentTitle),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _amountController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: CommonStrings.amount,
                  suffixText: widget.currency,
                  hintText: "0",
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                ],
                validator: (value) {
                  if (value == null || value.isEmpty)
                    return CommonStrings.fieldCannotBeEmpty;
                  if (double.tryParse(value.replaceAll(',', '.')) == null)
                    return "Invalid number";
                  if (double.parse(value.replaceAll(',', '.')) == 0)
                    return "Amount cannot be 0";
                  return null;
                },
                onTap: () => _amountController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _amountController.value.text.length),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4.0, bottom: 8.0),
                child: Text(
                  OrdersStrings.enterCashAmountDescription,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ExpansionTile(
                title: Text(
                  CommonStrings.advancedSettings,
                  style: TextStyle(
                    color: Theme.of(context).hintColor,
                    fontSize: 12,
                  ),
                ),
                tilePadding: EdgeInsets.zero,
                children: [
                  InkWell(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setState(() {
                          _selectedDate = picked;
                        });
                      }
                    },
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: CommonStrings.date,
                      ),
                      child: Text(DateFormat.yMd(
                              Localizations.localeOf(context).toString())
                          .format(_selectedDate)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _noteController,
                    decoration: InputDecoration(
                      labelText: CommonStrings.note,
                    ),
                    maxLines: 1,
                  ),
                ],
              ),
              if (widget.isBankAdmin) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Text(CommonStrings.or.toUpperCase(),
                          style: TextStyle(color: Colors.grey, fontSize: 12)),
                    ),
                    Expanded(child: Divider()),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16.0, bottom: 8.0),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop('SWITCH_TO_CASHLESS');
                      },
                      icon: Icon(Icons.account_balance, size: 18),
                      label: Text(OrdersStrings.findAndLinkTransaction),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).primaryColor,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(CommonStrings.storno),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(OrdersStrings.addPayment),
        ),
      ],
    );
  }
}
