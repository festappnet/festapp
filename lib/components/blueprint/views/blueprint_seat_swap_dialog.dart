import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:fstapp/components/eshop/ticket_commands.dart';
import 'package:fstapp/components/eshop/ticket_cancellation_updates.dart';
import 'package:fstapp/components/eshop/views/product_info_panel.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../blueprint_seat_swap_preview.dart';
import '../blueprint_strings.dart';

/// Keep the completed operation open while the operator reviews customer updates.
class BlueprintSeatSwapDialog extends StatefulWidget {
  const BlueprintSeatSwapDialog({
    super.key,
    this.preview,
    this.initialOutcome,
    this.onSwap,
    this.onSwapped,
  });
  final BlueprintSeatSwapPreview? preview;
  final SeatSwapOutcome? initialOutcome;
  final Future<SeatSwapOutcome> Function()? onSwap;
  final Future<void> Function(SeatSwapOutcome)? onSwapped;

  @override
  State<BlueprintSeatSwapDialog> createState() =>
      _BlueprintSeatSwapDialogState();
}

class _BlueprintSeatSwapDialogState extends State<BlueprintSeatSwapDialog> {
  SeatSwapOutcome? _outcome;
  List<TicketDetailsBundle> _updates = [];
  final _notifiedRecipients = <String>{};
  bool _working = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _outcome = widget.initialOutcome;
    if (_outcome != null) {
      _working = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadUpdates(closeIfEmpty: true);
      });
    }
  }

  void _close() {
    if (!_working && !_sending) Navigator.of(context).pop(_outcome != null);
  }

  String _recipient(TicketDetailsBundle bundle) =>
      (bundle.order.data?['email'] as String? ?? '').trim().toLowerCase();

  Future<void> _loadUpdates({bool closeIfEmpty = false}) async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final byRecipient = <String, List<TicketDetailsBundle>>{};
      // A permutation inside one order needs no customer notification. Keep
      // meaningful price/payment changes (such as moving to a free pricier seat).
      if (_outcome!.orderIds.length > 1 || _outcome!.hasFinancialChanges) {
        for (final id in _outcome!.orderIds) {
          final bundle = await loadOrderUpdateEmail(id);
          if (!mounted) return;
          if (bundle == null) continue;
          final recipient = _recipient(bundle);
          if (recipient.isNotEmpty) {
            byRecipient.putIfAbsent(recipient, () => []).add(bundle);
          }
        }
      }
      // Two affected orders of one customer must not become two offers, nor
      // one arbitrary partial order update. A within-customer swap offers none.
      final updates = [
        for (final entry in byRecipient.entries)
          if (entry.value.length == 1 &&
              !_notifiedRecipients.contains(entry.key) &&
              entry.value.single.changes.hasChanges)
            entry.value.single,
      ];
      if (!mounted) return;
      setState(() {
        _updates = updates;
        _working = false;
      });
      if (updates.isEmpty && closeIfEmpty) _close();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = OrdersStrings.sendEmailFailed;
          _working = false;
        });
      }
    }
  }

  Future<void> _swap() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final outcome = await widget.onSwap!();
      if (!mounted) return;
      setState(() => _outcome = outcome);
      await widget.onSwapped?.call(outcome);
      if (mounted) await _loadUpdates(closeIfEmpty: true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = BlueprintStrings.layoutErrorMessage(error);
          _working = false;
        });
      }
    }
  }

  Future<void> _send(TicketDetailsBundle bundle) async {
    setState(() => _sending = true);
    try {
      final dispatched = await showOrderUpdateEmails(context, [
        bundle.order.id!,
      ], onlyIfChanged: true);
      if (dispatched.contains(bundle.order.id)) {
        _notifiedRecipients.add(_recipient(bundle));
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        await _loadUpdates();
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_working && !_sending,
    child: AppAlertDialog(
      dismissible: !_working && !_sending,
      onClose: _close,
      title: Text(
        _outcome == null
            ? BlueprintStrings.legendSwapSeats
            : BlueprintStrings.swapSuccess,
      ),
      content: SizedBox(
        width: 520,
        height: (MediaQuery.sizeOf(context).height * .6)
            .clamp(240.0, 520.0)
            .toDouble(),
        child: _working
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    if (_outcome != null)
                      TextButton(
                        onPressed: _loadUpdates,
                        child: Text(CommonStrings.retry),
                      ),
                  ],
                  Expanded(
                    child: _outcome == null
                        ? _preview(context)
                        : ListView(
                            children: [
                              for (final bundle in _updates)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${BlueprintStrings.orderLabel} ${bundle.order.orderSymbol ?? bundle.order.id}',
                                      ),
                                      ProductInfoPanel(
                                        order: bundle.order,
                                        paymentInfo: bundle.paymentInfo,
                                        ticket: bundle.ticket,
                                        orderHistory: bundle.orderHistory,
                                        onSendUpdate: _sending
                                            ? null
                                            : () => _send(bundle),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _working || _sending ? null : _close,
          child: Text(
            _outcome == null ? CommonStrings.storno : CommonStrings.close,
          ),
        ),
        if (_outcome == null)
          FilledButton(
            onPressed: _working ? null : _swap,
            child: Text(BlueprintStrings.legendSwapSeats),
          ),
      ],
    ),
  );

  Widget _preview(BuildContext context) => ListView.builder(
    itemCount: widget.preview!.seats.length + widget.preview!.orders.length,
    itemBuilder: (context, index) {
      if (index < widget.preview!.seats.length) {
        final seat = widget.preview!.seats[index];
        return ListTile(
          title: Text(seat.title ?? '#${seat.id}'),
          subtitle: Text(
            [
              widget.preview!.sourceIds.contains(seat.id)
                  ? BlueprintStrings.swapSourceSeats
                  : BlueprintStrings.swapTargetSeats,
              BlueprintStrings.seatState(seat.state),
              seat.productTitle,
              seat.customerName,
              seat.customerSurname,
              seat.customerEmail,
              if (seat.ticketId != null)
                '${BlueprintStrings.ticketLabel}: ${seat.ticketId}',
            ].whereType<String>().where((s) => s.isNotEmpty).join(' - '),
          ),
        );
      }
      final moneyIndex = index - widget.preview!.seats.length;
      if (moneyIndex < widget.preview!.orders.length) {
        final order = widget.preview!.orders[moneyIndex];
        return ListTile(
          title: Text('${BlueprintStrings.orderLabel} ${order.orderId}'),
          subtitle: Text(
            '${Utilities.formatPrice(context, double.parse(order.beforeAmount), currencyCode: order.currencyCode)} → '
            '${Utilities.formatPrice(context, double.parse(order.afterAmount), currencyCode: order.currencyCode)}',
          ),
          trailing: Text(
            Utilities.formatPrice(
              context,
              double.parse(order.delta),
              currencyCode: order.currencyCode,
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    },
  );
}
