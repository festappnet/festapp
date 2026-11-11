import '../../../widgets/app_dialog.dart';
import '../../_shared/common_strings.dart';
import '../payment_operation_strings.dart';
import '../orders_strings.dart';

import 'package:material_ui/material_ui.dart';

import '../db_eshop.dart';
import '../db_orders.dart';
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
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _PaymentOperationFlow(orderId: orderId, unitId: unitId, refund: refund),
);

class _PaymentOperationFlow extends StatefulWidget {
  const _PaymentOperationFlow({
    required this.orderId,
    required this.unitId,
    required this.refund,
  });
  final int orderId, unitId;
  final bool refund;
  @override
  State<_PaymentOperationFlow> createState() => _PaymentOperationFlowState();
}

class _PaymentOperationFlowState extends State<_PaymentOperationFlow> {
  GetTransactionsForOrderResponse? _data;
  Map<String, dynamic>? _pendingPayload;
  late bool _refund = widget.refund;
  bool _loading = true, _loadFailed = false, _refreshing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final pending = await DbOrders.pendingPaymentOperation(widget.orderId);
      final data = await DbEshop.getTransactionsForOrder(widget.orderId);
      if (!mounted) return;
      final refund = pending != null
          ? pending['operation'] != 'record_payment'
          : widget.refund;
      final allowed =
          pending != null ||
          (refund
                  ? data?.paymentOperations.canRefund
                  : data?.paymentOperations.canRecord) ==
              true;
      setState(() {
        _refund = refund;
        _pendingPayload = pending;
        _data = allowed && data?.paymentInfo?.currencyCode != null
            ? data
            : null;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _configure() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(PaymentMethodStrings.text('configureBank')),
          ),
          body: UnitBankAccountsScreen(
            unitId: _data!.actions.unitId ?? widget.unitId,
          ),
        ),
      ),
    );
    if (!mounted) return;
    setState(() => _refreshing = true);
    try {
      final updated = await DbEshop.getTransactionsForOrder(widget.orderId);
      if (mounted && updated != null) {
        setState(() {
          _data = updated;
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
        paymentInfoId: _data!.paymentInfo!.id!,
        bankAccount: account,
        readOnly: readOnly,
      ),
    );
    if (mounted && changed == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _loadFailed || _data == null) {
      return AppAlertDialog(
        onClose: () => Navigator.of(context).pop(),
        title: Text(
          _refund
              ? PaymentOperationStrings.text('refund')
              : OrdersStrings.addCashPaymentTitle,
        ),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(CommonStrings.loading),
              ] else
                Text(
                  PaymentOperationStrings.text(
                    _loadFailed ? 'loadFailed' : 'unavailable',
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(CommonStrings.close),
          ),
          if (_loadFailed)
            TextButton(onPressed: _load, child: Text(CommonStrings.retry)),
        ],
      );
    }
    return PaymentOperationDialog(
      orderId: widget.orderId,
      context: _data!.paymentOperations,
      refund: _refund,
      refundRecipients: PaymentRefundRecipient.fromTransactions(
        _data!.transactions,
        _data!.paymentInfo!.currencyCode!,
      ),
      initialPendingPayload: _pendingPayload,
      currency: _data!.paymentInfo!.currencyCode!,
      bankOptions: OrderPaymentBankOptions(
        actions: _data!.actions,
        onConfigure: _refreshing ? null : _configure,
        onPair: _data!.actions.pairingAccountId == null
            ? null
            : () => _search(_data!.actions.pairingAccountId!, readOnly: false),
        onHistory: (PaymentHistoryAccount account) =>
            _search(account.id, readOnly: true),
      ),
    );
  }
}
