import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/widgets/standard_dialog.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:fstapp/components/html/editable_html_field.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class ProductDetailEditorDialog extends StatefulWidget {
  final ProductModel product;
  final HtmlSaveCoordinator? coordinator;
  const ProductDetailEditorDialog({super.key, required this.product, this.coordinator});

  @override
  _ProductDetailEditorDialogState createState() =>
      _ProductDetailEditorDialogState();
}

class _ProductDetailEditorDialogState extends State<ProductDetailEditorDialog> {
  late String _description;
  late TextEditingController _quantityController;
  late TextEditingController _shortTitleController;

  @override
  void initState() {
    super.initState();
    _description = widget.product.description ?? "";
    _quantityController =
        TextEditingController(text: widget.product.maximum?.toString() ?? "0");
    _quantityController.addListener(() {
      widget.product.maximum = int.tryParse(_quantityController.text) ?? 0;
    });
    _shortTitleController =
        TextEditingController(text: widget.product.shortTitle ?? "");
    _shortTitleController.addListener(() {
      widget.product.shortTitle = _shortTitleController.text;
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _shortTitleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StandardDialog(
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 32),
            SelectableText(
              widget.product.title ?? '',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (FeatureService.isFeatureEnabled(FeatureConstants.ticket)) ...[
              const SizedBox(height: 16),
              TextField(
                controller: _shortTitleController,
                decoration: InputDecoration(
                  labelText: OrdersStrings.gridShortTitle,
                  border: const UnderlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 8),
            // Editable Product Quantity with helper text
            TextField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: FormStrings.productQuantity,
                helperText: FormStrings.enterZeroForUnlimited,
                border: const UnderlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            // Product Description Title
            Text(
              CommonStrings.description,
            ),
            const SizedBox(height: 8),
            // Full HTML description (no height limit)
            EditableHtmlField(html: _description, coordinator: widget.coordinator,
              owner: HtmlMediaOwner.occasion(widget.product.occasion),
              onChanged: (html) => setState(() { _description = html; widget.product.description = html; })),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
