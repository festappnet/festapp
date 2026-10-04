import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/html/html_helper.dart';
import 'product_detail_editor_dialog.dart';
import 'ticket_editor_widgets.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'description_tooltip.dart';

class TicketProductEditorRow extends StatefulWidget {
  final ProductModel product;
  final VoidCallback onDelete;
  final List<String> availableCurrencies;

  const TicketProductEditorRow({
    super.key,
    required this.product,
    required this.onDelete,
    required this.availableCurrencies,
  });

  @override
  _TicketProductEditorRowState createState() => _TicketProductEditorRowState();
}

class _TicketProductEditorRowState extends State<TicketProductEditorRow> {
  late TextEditingController _titleController;
  late TextEditingController _priceController;
  late TextEditingController _depositController;
  late TextEditingController _metaSurchargeController;
  late TextEditingController _surchargeCurrencyController;
  late String selectedCurrency;
  String? _depositError;

  bool get _isVirtualMode => FeatureService.isDepositVirtualMode();

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.product.title ?? "");
    _priceController =
        TextEditingController(text: (widget.product.price ?? 0).toString());
    _depositController = TextEditingController(
        text: widget.product.depositAmount?.toString() ?? "");
    _metaSurchargeController = TextEditingController(
        text: widget.product.metaSurchargeAmount?.toString() ?? "");
    _surchargeCurrencyController = TextEditingController(
        text: widget.product.metaSurchargeCurrency ?? "");
    _titleController.addListener(() {
      widget.product.title = _titleController.text;
    });
    _priceController.addListener(() {
      final text = _priceController.text.replaceAll(RegExp(r'\s+'), '');
      final newPrice = double.tryParse(text);
      if (newPrice != null) {
        widget.product.price = newPrice;
      }
      _validateDeposit();
    });
    _depositController.addListener(_validateDeposit);
    _metaSurchargeController.addListener(_onMetaSurchargeChanged);
    _surchargeCurrencyController.addListener(_onSurchargeCurrencyChanged);
    // Initialize the selected currency from the product model or default to the first available.
    selectedCurrency = widget.product.currencyCode ??
        (widget.availableCurrencies.isNotEmpty
            ? widget.availableCurrencies.first
            : '');
    widget.product.currencyCode = selectedCurrency;
  }

  void _validateDeposit() {
    final depositText = _depositController.text.replaceAll(RegExp(r'\s+'), '');
    final priceText = _priceController.text.replaceAll(RegExp(r'\s+'), '');
    final deposit = depositText.isNotEmpty ? double.tryParse(depositText) : null;
    final price = double.tryParse(priceText) ?? 0;

    setState(() {
      if (deposit != null && deposit > 0 && deposit >= price) {
        _depositError = "< ${CommonStrings.price}";
      } else {
        _depositError = null;
      }
      // Keep the entered value on the model — backend validates on save and surfaces
      // a server-side error toast if the value is still invalid at submit time.
      widget.product.depositAmount = (deposit != null && deposit > 0) ? deposit : null;
    });
  }

  void _onMetaSurchargeChanged() {
    final t = _metaSurchargeController.text.replaceAll(RegExp(r'\s+'), '');
    final parsed = t.isEmpty ? null : double.tryParse(t);
    // Allow negative amounts (slevy / discounts); only null/0 clears the field.
    widget.product.metaSurchargeAmount =
        (parsed != null && parsed != 0) ? parsed : null;
  }

  void _onSurchargeCurrencyChanged() {
    final raw = _surchargeCurrencyController.text.trim().toUpperCase();
    final t = raw.length > 3 ? raw.substring(0, 3) : raw;
    widget.product.metaSurchargeCurrency = t.isEmpty ? null : t;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _depositController.dispose();
    _metaSurchargeController.dispose();
    _surchargeCurrencyController.dispose();
    super.dispose();
  }

  // Builds a select box for the given currency value + onSelected callback.
  Widget _buildCurrencyBox(String value, ValueChanged<String> onSelected) {
    if (widget.availableCurrencies.length > 1) {
      return InkWell(
        onTap: () async {
          final result = await showDialog<String>(
            context: context,
            builder: (context) {
              return SimpleDialog(
                title: Text(CommonStrings.currency),
                children: widget.availableCurrencies.map((currency) {
                  return SimpleDialogOption(
                    onPressed: () => Navigator.pop(context, currency),
                    child: Text(currency, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
              );
            },
          );
          if (result != null) onSelected(result);
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey),
            borderRadius: BorderRadius.circular(4.0),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
          child: Text(value, style: const TextStyle(fontSize: 14)),
        ),
      );
    } else {
      return Text(value, style: const TextStyle(fontSize: 14));
    }
  }

  Widget buildCurrencySelectBox() => _buildCurrencyBox(selectedCurrency, (v) {
        setState(() {
          selectedCurrency = v;
          widget.product.currencyCode = selectedCurrency;
        });
      });

  /// Free-text ISO currency input for the meta surcharge.
  /// Unlike the product price currency, this isn't tied to bank-configured
  /// currencies — surcharge is informational only, so any 3-letter code is valid.
  Widget buildSurchargeCurrencyField() {
    return SizedBox(
      width: 64,
      child: TextField(
        controller: _surchargeCurrencyController,
        maxLength: 3,
        textCapitalization: TextCapitalization.characters,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          hintText: 'EUR',
          counterText: '',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          border: OutlineInputBorder(),
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveOpacity = (widget.product.isHidden ?? false) ? 0.5 : 1.0;
    return Opacity(
      opacity: effectiveOpacity,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left column: Title field with product quantity directly below.
            Expanded(
              flex: 7,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: CommonStrings.title,
                      border: const UnderlineInputBorder(),
                      suffixIcon: (!HtmlHelper.isHtmlEmptyOrNull(
                              widget.product.description))
                          ? DescriptionTooltip(
                              description: widget.product.description!,
                              child: const Icon(Icons.description, size: 20),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.stacked_bar_chart, size: 16),
                      const SizedBox(width: 4),
                      SelectableText(
                        TicketEditorWidgets.formatOrderedCount(
                            widget.product.orderedCount,
                            widget.product.maximum),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Middle column: Price field and currency selection below it.
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _priceController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: CommonStrings.price,
                      border: const UnderlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.monetization_on, size: 16),
                      const SizedBox(width: 4),
                      buildCurrencySelectBox(),
                    ],
                  ),
                  if (FeatureService.isFeatureEnabled(
                      FeatureConstants.deposit)) ...[
                    const SizedBox(height: 8),
                    if (_isVirtualMode) ...[
                      // Virtual mode: visual-only "doplatek" amount (negative = sleva)
                      // with its OWN currency (can differ from product price currency).
                      TextField(
                        controller: _metaSurchargeController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true, signed: true),
                        decoration: InputDecoration(
                          labelText: OrdersStrings.gridSurcharge,
                          border: const UnderlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.monetization_on, size: 16),
                          const SizedBox(width: 4),
                          buildSurchargeCurrencyField(),
                        ],
                      ),
                    ] else
                      // Real mode: payment-linked deposit (positive only, shares product currency).
                      TextField(
                        controller: _depositController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: OrdersStrings.gridDeposit,
                          border: const UnderlineInputBorder(),
                          isDense: true,
                          errorText: _depositError,
                        ),
                      ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Right column: Visibility switch.
            Column(
              children: [
                Text(FormStrings.show, style: Theme.of(context).textTheme.bodySmall),
                Switch(
                  value: !(widget.product.isHidden ?? false),
                  onChanged: (val) {
                    setState(() {
                      widget.product.isHidden = !val;
                    });
                  },
                ),
              ],
            ),
            // Additional settings popup.
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'additional_settings') {
                        final htmlCoordinator = HtmlEditingScope.maybeOf(context);
                  showDialog(
                    context: context,
                    builder: (context) =>
                        ProductDetailEditorDialog(product: widget.product, coordinator: htmlCoordinator),
                  ).then((_) {
                    setState(() {}); // Refresh when dialog is closed.
                  });
                }
              },
              itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                PopupMenuItem<String>(
                  value: 'additional_settings',
                  child: Text(FormStrings.additionalSettings),
                ),
              ],
              icon: const Icon(Icons.more_vert),
            ),
            if (widget.product.id == null)
              IconButton(
                icon: const Icon(Icons.delete),
                onPressed: widget.onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
