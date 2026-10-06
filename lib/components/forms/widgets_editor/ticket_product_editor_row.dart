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
  final VoidCallback? onChanged;
  final List<String> availableCurrencies;

  const TicketProductEditorRow({
    super.key,
    required this.product,
    required this.onDelete,
    this.onChanged,
    required this.availableCurrencies,
  });

  @override
  _TicketProductEditorRowState createState() => _TicketProductEditorRowState();
}

class _TicketProductEditorRowState extends State<TicketProductEditorRow> {
  void _refresh(VoidCallback change) {
    setState(change);
    widget.onChanged?.call();
  }

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
    _surchargeCurrencyController =
        TextEditingController(text: widget.product.metaSurchargeCurrency ?? "");
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
    final deposit =
        depositText.isNotEmpty ? double.tryParse(depositText) : null;
    final price = double.tryParse(priceText) ?? 0;

    _refresh(() {
      if (deposit != null && deposit > 0 && deposit >= price) {
        _depositError = "< ${CommonStrings.price}";
      } else {
        _depositError = null;
      }
      // Keep the entered value on the model — backend validates on save and surfaces
      // a server-side error toast if the value is still invalid at submit time.
      widget.product.depositAmount =
          (deposit != null && deposit > 0) ? deposit : null;
    });
  }

  void _onMetaSurchargeChanged() {
    final t = _metaSurchargeController.text.replaceAll(RegExp(r'\s+'), '');
    final parsed = t.isEmpty ? null : double.tryParse(t);
    // Allow negative amounts (slevy / discounts); only null/0 clears the field.
    widget.product.metaSurchargeAmount =
        (parsed != null && parsed != 0) ? parsed : null;
    widget.onChanged?.call();
  }

  void _onSurchargeCurrencyChanged() {
    final raw = _surchargeCurrencyController.text.trim().toUpperCase();
    final t = raw.length > 3 ? raw.substring(0, 3) : raw;
    widget.product.metaSurchargeCurrency = t.isEmpty ? null : t;
    widget.onChanged?.call();
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
        _refresh(() {
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
    final colors = Theme.of(context).colorScheme;
    final hasDeposit = FeatureService.isFeatureEnabled(
      FeatureConstants.deposit,
    );
    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: CommonStrings.title,
            border: const UnderlineInputBorder(),
            suffixIcon:
                !HtmlHelper.isHtmlEmptyOrNull(widget.product.description)
                ? DescriptionTooltip(
                    description: widget.product.description!,
                    child: const Icon(Icons.description, size: 20),
                  )
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.stacked_bar_chart, size: 16),
            const SizedBox(width: 4),
            SelectableText(
              TicketEditorWidgets.formatOrderedCount(
                widget.product.orderedCount,
                widget.product.maximum,
              ),
            ),
          ],
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Column(
          children: [
            Text(
              FormStrings.show,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Switch(
              value: !(widget.product.isHidden ?? false),
              onChanged: (value) {
                _refresh(() => widget.product.isHidden = !value);
              },
            ),
          ],
        ),
        PopupMenuButton<String>(
          onSelected: (value) {
            if (value == 'additional_settings') {
              final coordinator = HtmlEditingScope.maybeOf(context);
              showDialog(
                context: context,
                builder: (context) => ProductDetailEditorDialog(
                  product: widget.product,
                  coordinator: coordinator,
                ),
              ).then((_) {
                if (mounted) _refresh(() {});
              });
            }
          },
          itemBuilder: (_) => [
            PopupMenuItem(
              value: 'additional_settings',
              child: Text(FormStrings.additionalSettings),
            ),
          ],
          icon: const Icon(Icons.more_vert),
        ),
        IconButton(
          tooltip: widget.product.canDelete
              ? CommonStrings.delete
              : FormStrings.deletionReason(widget.product.deleteBlockedReason),
          icon: const Icon(Icons.delete),
          onPressed: widget.product.canDelete ? widget.onDelete : null,
        ),
      ],
    );
    Widget amountField(
      TextEditingController controller,
      String label,
      Widget currency, {
      bool signed = false,
      String? error,
    }) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.numberWithOptions(
                decimal: true,
                signed: signed,
              ),
              decoration: InputDecoration(
                labelText: label,
                border: const UnderlineInputBorder(),
                errorText: error,
              ),
            ),
          ),
          const SizedBox(width: 12),
          currency,
        ],
      ),
    );
    final price = amountField(
      _priceController,
      CommonStrings.price,
      buildCurrencySelectBox(),
    );
    final extra = !hasDeposit
        ? null
        : _isVirtualMode
        ? amountField(
            _metaSurchargeController,
            OrdersStrings.gridSurcharge,
            buildSurchargeCurrencyField(),
            signed: true,
          )
        : amountField(
            _depositController,
            OrdersStrings.gridDeposit,
            Text(selectedCurrency),
            error: _depositError,
          );

    return Opacity(
      opacity: (widget.product.isHidden ?? false) ? .5 : 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 480 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.4;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                title,
                const SizedBox(height: 8),
                Align(alignment: Alignment.centerRight, child: actions),
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: 16),
                    actions,
                  ],
                ),
              const SizedBox(height: 16),
              if (compact || extra == null) ...[
                price,
                if (extra != null) ...[const SizedBox(height: 12), extra],
              ] else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: price),
                    const SizedBox(width: 16),
                    Expanded(child: extra),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
