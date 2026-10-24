import 'package:flutter/material.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/email_delivery/order_email_issue.dart';
import 'package:fstapp/components/email_delivery/email_delivery_strings.dart';
import 'package:fstapp/components/email_delivery/email_delivery_history.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action_confirmation.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../order_commands.dart';
import '../db_orders.dart';
import '../models/order_model.dart';
import '../order_item_strings.dart';
import '../orders_strings.dart';

class OrderEmailRepairDialog extends StatefulWidget {
  const OrderEmailRepairDialog(
      {super.key,
      required this.orderId,
      required this.occasionId,
      this.sourceMessageId,
      this.read,
      this.commands,
      this.canWrite,
      this.onChanged,
      this.onShowOrder});
  final VoidCallback? onShowOrder;
  final int orderId;
  final int occasionId;
  final String? sourceMessageId;
  final Future<dynamic> Function(String, Map<String, dynamic>)? read;
  final OrderCommands? commands;
  final bool? canWrite;
  final Future<void> Function()? onChanged;
  @override
  State<OrderEmailRepairDialog> createState() => _OrderEmailRepairDialogState();
}

class _OrderEmailRepairDialogState extends State<OrderEmailRepairDialog> {
  final _email = TextEditingController();
  late final OrderCommands _commands =
      widget.commands ?? SupabaseOrderCommands(Supabase.instance.client);
  Map<String, dynamic>? _order, _summary;
  bool _busy = false, _loading = true, _stale = false;
  String? _feedback, _selectedMessage;
  int _generation = 0;
  bool get _sameContext =>
      mounted &&
      (widget.read != null ||
          RightsService.currentOccasionId() == widget.occasionId);
  String t(String key) => EmailDeliveryStrings.recovery(key);
  Future<dynamic> _read(String name, Map<String, dynamic> args) =>
      widget.read?.call(name, args) ??
      Supabase.instance.client.rpc(name, params: args);
  @override
  void initState() {
    super.initState();
    RightsService.occasionLinkModelNotifier.addListener(_contextChanged);
    _load();
  }

  void _contextChanged() {
    if (_sameContext) return;
    _generation++;
    _order = null;
    _summary = null;
    if (mounted) Navigator.of(context).removeRoute(ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    RightsService.occasionLinkModelNotifier.removeListener(_contextChanged);
    _generation++;
    _email.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final history =
          await _read('get_order_history', {'order_id': widget.orderId});
      if (history['code'] != 200 ||
          history['data']['order']['occasion'] != widget.occasionId) {
        throw StateError('order unavailable');
      }
      final summary =
          await _read('get_order_email_summary', {'p_order': widget.orderId});
      if (!_sameContext || generation != _generation) return;
      setState(() {
        _order = Map<String, dynamic>.from(history['data']['order']);
        _summary = Map<String, dynamic>.from(summary);
        _email.text = _order!['data']['email']?.toString() ?? '';
        _loading = false;
        _stale = false;
      });
    } catch (_) {
      if (!_sameContext || generation != _generation) return;
      setState(() {
        _loading = false;
        _stale = true;
        _feedback = t('unavailable');
      });
    }
  }

  Future<void> _save(bool resend, OrderEmailIssue? issue) async {
    if (_busy || _order == null || !_sameContext) return;
    setState(() {
      _busy = true;
      _feedback = null;
    });
    try {
      final result = await _commands.repairEmail(
          orderId: widget.orderId,
          expectedEmail: _order!['data']['email'] ?? '',
          expectedState: _order!['state'],
          expectedPaymentFingerprint:
              _order!['email_payment_fingerprint'] as String,
          expectedPaymentVersion:
              (_order!['email_payment_version'] as num).toInt(),
          email: _email.text,
          sourceMessageId: issue?.messageId,
          resend: resend);
      if (!_sameContext) return;
      await _load();
      if (!_sameContext) return;
      setState(() => _feedback = t(result['code'] == 409
          ? 'conflict'
          : resend
              ? 'queued'
              : 'saved'));
      OrderEmailIssue.changes.value++;
      await widget.onChanged?.call();
    } catch (error) {
      if (_sameContext)
        setState(() => _feedback = t(error is PostgrestException &&
                error.message.contains('email_recipient_suppressed')
            ? 'blocked'
            : 'failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy || _order == null) return;
    final order = OrderModel.fromJson(_order!);
    final confirmed = await DataGridActionConfirmation.show<OrderModel>(
        context: context,
        title: t('cancel'),
        message:
            '${OrderItemStrings.cancelOrdersConfirmationText}\n${t('refund')}',
        items: [order],
        itemsLabel: OrdersStrings.ordersTab,
        confirmButtonText: t('cancel'));
    if (!confirmed || !_sameContext) return;
    setState(() => _busy = true);
    try {
      await DbOrders.stornoOrder(widget.orderId);
      if (!_sameContext) return;
      await _load();
      OrderEmailIssue.changes.value++;
      await widget.onChanged?.call();
    } catch (error) {
      if (_sameContext)
        setState(() => _feedback = t(error is PostgrestException &&
                error.message.contains('email_recipient_suppressed')
            ? 'blocked'
            : 'failed'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issues = OrderEmailIssue.fromSummary(_summary);
    final selected = issues
            .where((i) =>
                i.messageId == (_selectedMessage ?? widget.sourceMessageId) ||
                i.sourceId == (_selectedMessage ?? widget.sourceMessageId))
            .firstOrNull ??
        issues.firstOrNull;
    final writable = !_stale &&
        (widget.canWrite ?? RightsService.canUpdateOrders()) &&
        const ['ordered', 'paid', 'sent'].contains(_order?['state']);
    final uncertain = issues.any((i) => i.uncertain);
    final recipientBlocked = issues.any((i) => i.blocksRecipient(_email.text));
    return AppDialog(
        dismissible: !_busy,
        child: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AppDialogHeader(
                              title: Text(
                                  '${t('title')} ${_order?['order_symbol'] ?? ''}'),
                              closeEnabled: !_busy),
                          if (widget.onShowOrder != null)
                            TextButton(
                                onPressed: widget.onShowOrder,
                                child: Text(t('show'))),
                          if (_loading)
                            const Center(child: CircularProgressIndicator()),
                          if (_stale) Text(t('stale')),
                          if (_order != null) ...[
                            Text([
                              _order!['data']['name'],
                              _order!['data']['surname']
                            ].whereType<String>().join(' ')),
                            Text(
                                '${t('current')}: ${_order!['data']['email'] ?? ''}'),
                            for (final issue in issues)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: DecoratedBox(
                                      decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .errorContainer,
                                          borderRadius:
                                              BorderRadius.circular(8)),
                                      child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: DefaultTextStyle(
                                              style: TextStyle(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onErrorContainer),
                                              child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    const Icon(Icons
                                                        .warning_amber_rounded),
                                                    Text(issue.description),
                                                    if (issue
                                                            .reasonDescription !=
                                                        null)
                                                      Text(issue
                                                          .reasonDescription!),
                                                    if (issues.length > 1)
                                                      TextButton(
                                                          onPressed: _busy
                                                              ? null
                                                              : () => setState(() =>
                                                                  _selectedMessage =
                                                                      issue
                                                                          .messageId),
                                                          child: Text(issue ==
                                                                  selected
                                                              ? '✓ ${t('resolve')}'
                                                              : t('resolve'))),
                                                    if (issue
                                                            .originalRecipient !=
                                                        _order!['data']
                                                            ['email'])
                                                      Text(
                                                          '${t('original')}: ${issue.originalRecipient}'),
                                                    if (issue
                                                            .data['obsolete'] ==
                                                        true)
                                                      Text(t('obsolete')),
                                                  ]))))),
                            if (_order!['state'] == 'storno')
                              Text(t('cancelled')),
                            if (uncertain) Text(t('uncertain')),
                            if (recipientBlocked) Text(t('blocked')),
                            if (!writable && _order!['state'] != 'storno')
                              Text(t('readonly')),
                            if (writable) ...[
                              TextField(
                                  controller: _email,
                                  onChanged: (_) => setState(() {}),
                                  enabled: !_busy,
                                  keyboardType: TextInputType.emailAddress,
                                  decoration:
                                      InputDecoration(labelText: t('email'))),
                              const SizedBox(height: 12),
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () => _save(false, selected),
                                    child: Text(t('save'))),
                                OutlinedButton(
                                    onPressed: _busy ||
                                            uncertain ||
                                            recipientBlocked ||
                                            (selected != null &&
                                                !selected.canResend)
                                        ? null
                                        : () => _save(true, selected),
                                    child: Text(t('resend'))),
                                if (selected?.data['obsolete'] == true)
                                  OutlinedButton(
                                      onPressed:
                                          _busy || uncertain || recipientBlocked
                                              ? null
                                              : () => _save(true, null),
                                      child: Text(t('sendCurrent'))),
                                TextButton(
                                    onPressed: _busy ? null : _cancel,
                                    child: Text(t('cancel'))),
                              ]),
                              Text(
                                  '${t('recipient')}: ${_email.text}\n${EmailDeliveryStrings.kind(_order!['state'] == 'ordered' ? 'order_confirmation' : 'order_tickets')}'),
                            ],
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => showDialog<void>(
                                        context: context,
                                        builder: (_) => EmailDeliveryHistory(
                                            occasionId: widget.occasionId,
                                            orderId: widget.orderId)),
                                child: Text(EmailDeliveryStrings.history)),
                          ],
                          if (_feedback != null)
                            Semantics(
                                liveRegion: true, child: Text(_feedback!)),
                          if (_stale)
                            TextButton(
                                onPressed: _busy ? null : _load,
                                child: Text(t('reload'))),
                        ])))));
  }
}
