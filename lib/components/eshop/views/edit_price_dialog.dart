import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class EditPriceDialog extends StatefulWidget {
  final double initialPrice;

  const EditPriceDialog({
    super.key,
    required this.initialPrice,
  });

  @override
  State<EditPriceDialog> createState() => _EditPriceDialogState();
}

class _EditPriceDialogState extends State<EditPriceDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _priceController;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _priceController =
        TextEditingController(text: widget.initialPrice.toStringAsFixed(2));
    _focusNode = FocusNode();

    // Add a short delay to allow the dialog animation to complete before focusing.
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) {
        // Check if the widget is still in the tree before requesting focus.
        _focusNode.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _priceController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context)
          .pop(double.parse(_priceController.text.replaceAll(",", ".")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 450),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                OrdersStrings.editPriceTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    focusNode: _focusNode,
                    controller: _priceController,
                    decoration:
                        InputDecoration(labelText: OrdersStrings.newPriceLabel),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: false),
                    onFieldSubmitted: (_) => _submit(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return OrdersStrings.priceValidationRequired;
                      }
                      final price = double.tryParse(value.replaceAll(",", "."));
                      if (price == null) {
                        return OrdersStrings.priceValidationInvalid;
                      }
                      if (price < 0) {
                        return OrdersStrings.priceValidationNegative;
                      }
                      return null;
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    child: Text(OrdersStrings.setToZeroButton),
                    onPressed: () {
                      _priceController.text = "0.00";
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    child: Text(CommonStrings.storno),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _submit,
                    child: Text(CommonStrings.ok),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
