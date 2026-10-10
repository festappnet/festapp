import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/eshop/models/product_model.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/eshop/views/search_products_screen.dart';
import 'order_update_email_dialog.dart';
import 'package:fstapp/components/eshop/views/product_info_panel.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

import '../orders_strings.dart';
import '../models/order_model.dart';
import 'edit_price_dialog.dart';

class ProductsDialog extends StatefulWidget {
  final int ticketId;
  const ProductsDialog({super.key, required this.ticketId});

  @override
  State<ProductsDialog> createState() => _ProductsDialogState();
}

class _ProductsDialogState extends State<ProductsDialog> {
  bool _loading = true;
  bool get _canEdit =>
      !_loading &&
      _bundle != null &&
      _bundle!.order.canEdit &&
      _bundle!.ticket.state != OrderModel.stornoState;
  TicketDetailsBundle? _bundle;
  List<ProductModel> _orig = [], _current = [];
  double _sumOrig = 0, _sumCur = 0;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    if (!mounted) return;
    setState(() => _loading = true);
    _bundle = await DbEshop.getProductsForTicket(widget.ticketId);
    if (_bundle != null) {
      _orig =
          _bundle!.ticket.relatedProducts?.map((p) => p.copyWith()).toList() ??
              [];
      _current =
          _bundle!.ticket.relatedProducts?.map((p) => p.copyWith()).toList() ??
              [];
      _recalc();
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  void _recalc() {
    _sumOrig = _orig.fold(0, (s, p) => s + (p.price ?? 0));
    _sumCur = _current.fold(0, (s, p) => s + (p.price ?? 0));
  }

  Future<void> _add() async {
    if (!_canEdit) return;
    final added = await Navigator.of(context).push<List<ProductModel>>(
      MaterialPageRoute(
        builder: (_) => SearchProductsScreen(
          ticketId: widget.ticketId,
          alreadySelected: _current,
        ),
      ),
    );
    if (added != null && added.isNotEmpty) {
      setState(() {
        _current.addAll(added);
        _recalc();
      });
    }
  }

  void _remove(ProductModel p) {
    if (!_canEdit) return;
    setState(() {
      _current.removeWhere((c) => c.id == p.id);
      _recalc();
    });
  }

  void _addBack(ProductModel p) {
    if (!_canEdit) return;
    setState(() {
      _current.add(p.copyWith());
      _recalc();
    });
  }

  Future<void> _editPrice(ProductModel product) async {
    if (!_canEdit) return;
    final newPrice = await showDialog<double>(
      context: context,
      builder: (context) {
        return EditPriceDialog(initialPrice: product.price ?? 0);
      },
    );

    if (newPrice != null) {
      setState(() {
        final pIndex = _current.indexWhere((p) => p.id == product.id);
        if (pIndex != -1) {
          _current[pIndex].price = newPrice;
          _recalc();
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_canEdit) return;
    setState(() => _loading = true);
    try {
      // The rpc call now either returns the success data or throws an exception.
      await DbEshop.updateProductsForOrder(
        widget.ticketId,
        _current,
      );

      // If we reach here, the call was successful.
      if (mounted) {
        ToastHelper.Show(context, OrdersStrings.productsUpdateSuccess);
        _fetch(); // Refresh data
      }
    } catch (e) {
      // If the call fails, a PostgrestException will be caught here.
      if (mounted) {
        setState(() => _loading = false);
        // Show friendly toast — backend error message is extracted by ExceptionHandler.
        ExceptionHandler.handle(
          context,
          error: e,
          defaultMessage: OrdersStrings.productsUpdateFailed,
        );
      }
    }
  }

  bool get _hasUnsavedChanges => !const ListEquality<(int?, double?)>().equals(
      _orig.map((p) => (p.id, p.price)).toList(),
      _current.map((p) => (p.id, p.price)).toList());

  Future<void> _showSendUpdateConfirmDialog() async {
    if (!_canEdit || _hasUnsavedChanges) return;
    await _fetch();
    if (!mounted || !_canEdit) return;
    final order = _bundle?.order;
    final payment = _bundle?.paymentInfo;
    if (order == null) return;

    final confirmed = await showOrderUpdateEmailDialog(
      context,
      email: order.data?["email"] ?? "N/A",
      changes: _bundle!.changes,
      ticketId: widget.ticketId,
      balance: (order.price ?? 0) - (payment?.paid ?? 0),
    );

    if (confirmed && mounted) {
      setState(() => _loading = true);
      try {
        await DbEshop.sendTicketOrderUpdateEmail(_bundle!.order.id!);
      } catch (e) {
        if (mounted) {
          ToastHelper.Show(context, OrdersStrings.sendEmailFailed,
              severity: ToastSeverity.NotOk);
          setState(() => _loading = false);
          await _fetch();
          return;
        }
      }
      if (mounted) {
        ToastHelper.Show(context, OrdersStrings.sendEmailSuccess);
        await _fetch();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // figure out added vs removed
    final added =
        _current.where((p) => !_orig.any((o) => o.id == p.id)).toList();
    final removed =
        _orig.where((p) => !_current.any((c) => c.id == p.id)).toList();

    // build unified list: orig items first (incl. removed), then newly added
    final allItems = [..._orig, ...added];

    final customerName = _bundle?.order.data != null
        ? "${_bundle!.order.data!["name"] ?? ""} ${_bundle!.order.data!["surname"] ?? ""}"
        : OrdersStrings.dialogTitleFallback;

    // Combine order symbol and customer name for the title
    final dialogTitle =
        "${_bundle?.order.toBasicString() ?? ""} $customerName".trim();

    return AlertDialog(
      insetPadding: const EdgeInsets.all(16),
      titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      title: Row(
        children: [
          Expanded(child: SelectableText(dialogTitle)),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(false),
          )
        ],
      ),
      content: _loading
          ? const SizedBox(
              height: 120, child: Center(child: CircularProgressIndicator()))
          : SizedBox(
              width: StylesConfig.formMaxWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_bundle != null) ...[
                      ProductInfoPanel(
                        order: _bundle!.order,
                        paymentInfo: _bundle!.paymentInfo,
                        ticket: _bundle!.ticket,
                        orderHistory: _bundle!.orderHistory,
                        onSendUpdate: !_canEdit || _hasUnsavedChanges
                            ? null
                            : _showSendUpdateConfirmDialog,
                      ),
                      const Divider(height: 32),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildTotalColumn(
                            OrdersStrings.originalPrice, _sumOrig),
                        _buildTotalColumn(OrdersStrings.currentPrice, _sumCur),
                        _buildChangeColumn(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (allItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24.0),
                        child: SelectableText(OrdersStrings.noProducts),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: allItems.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final p = allItems[i];
                          final pCurrent =
                              _current.firstWhereOrNull((c) => c.id == p.id);
                          final pOrig =
                              _orig.firstWhereOrNull((o) => o.id == p.id);

                          final isAdded = added.any((x) => x.id == p.id);
                          final isRemoved = removed.any((x) => x.id == p.id);
                          final isPriceChanged = !isAdded &&
                              !isRemoved &&
                              pCurrent != null &&
                              pOrig != null &&
                              pCurrent.price != pOrig.price;

                          final priceText = isAdded
                              ? "+${Utilities.formatPrice(context, p.price ?? 0, decimalDigits: 2)}"
                              : isRemoved
                                  ? "-${Utilities.formatPrice(context, p.price ?? 0, decimalDigits: 2)}"
                                  : isPriceChanged
                                      ? "${Utilities.formatPrice(context, pCurrent.price ?? 0, decimalDigits: 2)} (${Utilities.formatPrice(context, pOrig.price ?? 0, decimalDigits: 2)})"
                                      : Utilities.formatPrice(
                                          context, p.price ?? 0,
                                          decimalDigits: 2);

                          final priceColor = isAdded
                              ? Colors.green
                              : isRemoved
                                  ? Colors.red
                                  : isPriceChanged
                                      ? Colors.orange.shade700
                                      : null;

                          return Card(
                            color: isAdded
                                ? Colors.green
                                    .withOpacityUniversal(context, 0.05)
                                : isRemoved
                                    ? Colors.red
                                        .withOpacityUniversal(context, 0.05)
                                    : isPriceChanged
                                        ? Colors.orange
                                            .withOpacityUniversal(context, 0.05)
                                        : null,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            elevation: 1,
                            child: ListTile(
                              title: SelectableText(p.title ?? ""),
                              subtitle: SelectableText(
                                  p.productTypeTitleString ?? ""),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SelectableText(
                                    priceText,
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: priceColor),
                                  ),
                                  const SizedBox(width: 8),
                                  if (!isRemoved)
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: OrdersStrings.editPriceTooltip,
                                      onPressed: !_canEdit || pCurrent == null
                                          ? null
                                          : () => _editPrice(pCurrent),
                                    ),
                                  IconButton(
                                    icon: Icon(isRemoved
                                        ? Icons.add
                                        : Icons.delete_outline),
                                    tooltip: isRemoved
                                        ? OrdersStrings.addBackTooltip
                                        : OrdersStrings.removeTooltip,
                                    onPressed: !_canEdit
                                        ? null
                                        : () => isRemoved
                                            ? _addBack(p)
                                            : _remove(p),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _canEdit ? _add : null,
                        icon: const Icon(Icons.add_shopping_cart),
                        label: Text(OrdersStrings.addProductsButton),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(CommonStrings.storno),
        ),
        ElevatedButton(
          onPressed: _canEdit && _hasUnsavedChanges ? _save : null,
          child: Text(CommonStrings.save),
        ),
      ],
    );
  }

  Widget _buildTotalColumn(String label, double sum) {
    return Column(
      children: [
        SelectableText(label,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(Utilities.formatPrice(context, sum, decimalDigits: 2)),
      ],
    );
  }

  Widget _buildChangeColumn() {
    final diff = _sumCur - _sumOrig;
    Color? color;
    String text;
    if (diff > 0) {
      color = Colors.green;
      text = "+${Utilities.formatPrice(context, diff, decimalDigits: 2)}";
    } else if (diff < 0) {
      color = Colors.red;
      text = Utilities.formatPrice(context, diff, decimalDigits: 2);
    } else {
      text = Utilities.formatPrice(context, diff, decimalDigits: 2);
    }

    return Column(
      children: [
        SelectableText(OrdersStrings.priceChange,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        SelectableText(
          text,
          style: color != null
              ? TextStyle(color: color, fontWeight: FontWeight.bold)
              : const TextStyle(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}
