import 'package:material_ui/material_ui.dart';

import '../db_eshop.dart';
import '../db_orders.dart';
import '../models/payment_operation_context.dart';
import '../models/payment_refund_recipient.dart';
import '../models/order_payment_actions.dart';
import '../../bank_accounts/views/unit_bank_accounts_screen.dart';
import '../../forms/payment_method_strings.dart';
import 'payment_operation_dialog.dart';
import 'order_payment_bank_options.dart';
import 'search_transactions_dialog.dart';

/// Both the grid and order detail enter through the same authorized read.
Future<bool?> showOrderPaymentOperationDialog(
  BuildContext context, {
  required int orderId,
  required int unitId,
  bool refund = false,
}) async {
  final pending = await DbOrders.pendingPaymentOperation(orderId);
  final recoveringRefund = pending != null
      ? pending['operation'] != 'record_payment'
      : refund;
  final data = await DbEshop.getTransactionsForOrder(orderId);
  if (!context.mounted ||
      (pending == null &&
          (recoveringRefund
                  ? data?.paymentOperations.canRefund
                  : data?.paymentOperations.canRecord) !=
              true) ||
      data?.paymentInfo == null) {
    return null;
  }
  final operationContext = await DbOrders.getPaymentOperationContext(orderId);
  if (!context.mounted) return null;
  return showDialog<bool>(
    context: context,
    builder: (_) => _PaymentOperationFlow(
      orderId: orderId,
      unitId: data!.actions.unitId ?? unitId,
      initial: data,
      operationContext: PaymentOperationContext.fromJson(operationContext),
      refund: recoveringRefund,
      initialPendingPayload: pending,
    ),
  );
}

class _PaymentOperationFlow extends StatefulWidget {
  const _PaymentOperationFlow({
    required this.orderId,
    required this.unitId,
    required this.initial,
    required this.operationContext,
    required this.refund,
    this.initialPendingPayload,
  });
  final int orderId, unitId;
  final bool refund;
  final Map<String, dynamic>? initialPendingPayload;
  final PaymentOperationContext operationContext;
  final GetTransactionsForOrderResponse initial;
  @override
  State<_PaymentOperationFlow> createState() => _PaymentOperationFlowState();
}

class _PaymentOperationFlowState extends State<_PaymentOperationFlow> {
  late GetTransactionsForOrderResponse _data = widget.initial;
  late PaymentOperationContext _operations = widget.operationContext;
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
      final operations = await DbOrders.getPaymentOperationContext(
        widget.orderId,
      );
      if (mounted && updated != null) {
        setState(() {
          _data = updated;
          _operations = PaymentOperationContext.fromJson(operations);
        });
      }
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
  Widget build(BuildContext context) => PaymentOperationDialog(
    orderId: widget.orderId,
    context: _operations,
    refund: widget.refund,
    refundRecipients: PaymentRefundRecipient.fromTransactions(
      _data.transactions,
      _data.paymentInfo!.currencyCode!,
    ),
    initialPendingPayload: widget.initialPendingPayload,
    currency: _data.paymentInfo!.currencyCode!,
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
