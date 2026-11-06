import 'package:material_ui/material_ui.dart';

import '../db_eshop.dart';
import '../models/order_payment_actions.dart';
import '../../bank_accounts/views/unit_bank_accounts_screen.dart';
import '../../forms/payment_method_strings.dart';
import 'add_cash_payment_dialog.dart';
import 'order_payment_bank_options.dart';
import 'search_transactions_dialog.dart';

/// Both the grid and order detail enter through the same authorized read.
Future<bool?> showOrderCashPaymentDialog(
  BuildContext context, {
  required int orderId,
  required int unitId,
}) async {
  final data = await DbEshop.getTransactionsForOrder(orderId);
  if (!context.mounted ||
      data?.actions.canAddCash != true ||
      data?.paymentInfo == null) {
    return null;
  }
  return showDialog<bool>(
    context: context,
    builder: (_) => _CashPaymentFlow(
      orderId: orderId,
      unitId: data!.actions.unitId ?? unitId,
      initial: data,
    ),
  );
}

class _CashPaymentFlow extends StatefulWidget {
  const _CashPaymentFlow({
    required this.orderId,
    required this.unitId,
    required this.initial,
  });
  final int orderId, unitId;
  final GetTransactionsForOrderResponse initial;
  @override
  State<_CashPaymentFlow> createState() => _CashPaymentFlowState();
}

class _CashPaymentFlowState extends State<_CashPaymentFlow> {
  late GetTransactionsForOrderResponse _data = widget.initial;
  bool _refreshing = false;
  Future<void> _configure() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(PaymentMethodStrings.text('configureBank')),
          ),
          body: UnitBankAccountsScreen(unitId: widget.unitId),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      final updated = await DbEshop.getTransactionsForOrder(widget.orderId);
      if (mounted && updated != null) setState(() => _data = updated);
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _search(int account, {required bool readOnly}) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => SearchTransactionsDialog(
        paymentInfoId: _data.paymentInfo!.id!,
        bankAccount: account,
        readOnly: readOnly,
      ),
    );
    if (mounted && changed == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => AddCashPaymentDialog(
    unitId: widget.unitId,
    currency: _data.paymentInfo!.currencyCode!,
    variableSymbol: _data.paymentInfo!.variableSymbol?.toString() ?? '',
    paymentInfoId: _data.paymentInfo!.id!,
    canSubmit: !_refreshing && _data.actions.canAddCash,
    bankOptions: OrderPaymentBankOptions(
      actions: _data.actions,
      onConfigure: _refreshing ? null : _configure,
      onPair: _data.actions.pairingAccountId == null
          ? null
          : () => _search(_data.actions.pairingAccountId!, readOnly: false),
      onHistory: (PaymentHistoryAccount account) =>
          _search(account.id, readOnly: true),
    ),
  );
}
