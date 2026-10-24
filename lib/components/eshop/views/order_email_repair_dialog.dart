import 'package:festapp_core/forms.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
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
  final _emailFocus = FocusNode();
  bool _emailTouched = false;
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
    _emailFocus.addListener(() {
      if (mounted) setState(() {
        if (!_emailFocus.hasFocus) _emailTouched = true;
      });
    });
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
    _emailFocus.dispose();
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
    if (_busy || _order == null || !_sameContext || !EmailAddress.isValid(_email.text.trim())) return;
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
      if (_sameContext) {
        setState(() => _feedback = t(error is PostgrestException &&
                error.message.contains('email_recipient_suppressed')
            ? 'blocked'
            : 'failed'));
      }
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
      if (_sameContext) {
        setState(() => _feedback = t(error is PostgrestException &&
                error.message.contains('email_recipient_suppressed')
            ? 'blocked'
            : 'failed'));
      }
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
    final theme = Theme.of(context);
    final secondaryStyle = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return AppAlertDialog(
      dismissible: !_busy,
      title: Text('${t('title')} ${_order?['order_symbol'] ?? ''}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loading) const Center(child: CircularProgressIndicator()),
              if (_stale) Text(t('stale')),
              if (_order != null) ...[
                Text(
                  [_order!['data']['name'], _order!['data']['surname']]
                      .whereType<String>()
                      .join(' '),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 4),
                Text('${t('current')}: ${_order!['data']['email'] ?? ''}',
                    style: secondaryStyle),
                if (widget.onShowOrder != null)
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () {
                              final showOrder = widget.onShowOrder;
                              Navigator.of(context).pop();
                              showOrder?.call();
                            },
                      child: Text(t('show'))),
                const Divider(height: 24),
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            size: 20, color: theme.colorScheme.error),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(issue.description,
                                  style: theme.textTheme.bodyMedium
                                      ?.copyWith(fontWeight: FontWeight.w600)),
                              if (issue.reasonDescription != null) ...[
                                const SizedBox(height: 4),
                                Text(issue.reasonDescription!,
                                    style: secondaryStyle),
                              ],
                              if (issues.length > 1)
                                TextButton.icon(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() =>
                                          _selectedMessage = issue.messageId),
                                  icon: Icon(
                                      issue == selected
                                          ? Icons.check
                                          : Icons.radio_button_unchecked,
                                      size: 18),
                                  label: Text(t('resolve')),
                                ),
                              if (issue.originalRecipient !=
                                  _order!['data']['email'])
                                Text(
                                    '${t('original')}: ${issue.originalRecipient}',
                                    style: secondaryStyle),
                              if (issue.data['obsolete'] == true)
                                Text(t('obsolete'), style: secondaryStyle),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_order!['state'] == 'storno') Text(t('cancelled')),
                if (uncertain)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(t('uncertain'))),
                if (recipientBlocked)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(t('blocked'))),
                if (!writable && _order!['state'] != 'storno')
                  Text(t('readonly')),
                if (writable) ...[
                  TextField(
                    controller: _email,
                    focusNode: _emailFocus,
                    onChanged: (_) => setState(() {}),
                    enabled: !_busy,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: t('email'),
                      helperText: t('emailHint'),
                      errorText: _emailTouched && !_emailFocus.hasFocus &&
                              !EmailAddress.isValid(_email.text.trim())
                          ? CommonStrings.invalidFormat : null,
                      helperMaxLines: 4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '${t('recipient')}: ${_email.text}\n${EmailDeliveryStrings.kind(_order!['state'] == 'ordered' ? 'order_confirmation' : 'order_tickets')}',
                    style: secondaryStyle,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => showDialog<void>(
                              context: context,
                              builder: (_) => EmailDeliveryHistory(
                                  occasionId: widget.occasionId,
                                  orderId: widget.orderId)),
                      icon: const Icon(Icons.history, size: 18),
                      label: Text(EmailDeliveryStrings.history),
                    ),
                    if (writable)
                      TextButton(
                        onPressed: _busy ? null : _cancel,
                        style: TextButton.styleFrom(
                            foregroundColor: theme.colorScheme.error),
                        child: Text(t('cancel')),
                      ),
                  ],
                ),
              ],
              if (_feedback != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(_feedback!)),
                ),
              if (_stale)
                TextButton(
                    onPressed: _busy ? null : _load, child: Text(t('reload'))),
            ],
          ),
        ),
      ),
      actions: [
        if (writable) ...[
          OutlinedButton(
              onPressed: _busy || !EmailAddress.isValid(_email.text.trim()) ? null : () => _save(false, selected),
              child: Text(t('save'))),
          if (selected?.data['obsolete'] == true)
            OutlinedButton(
                onPressed: _busy || !EmailAddress.isValid(_email.text.trim()) || uncertain || recipientBlocked
                    ? null
                    : () => _save(true, null),
                child: Text(t('sendCurrent'))),
          ElevatedButton(
              onPressed: _busy ||
                      !EmailAddress.isValid(_email.text.trim()) ||
                      uncertain ||
                      recipientBlocked ||
                      (selected != null && !selected.canResend)
                  ? null
                  : () => _save(true, selected),
              child: Text(t('resend'))),
        ],
      ],
    );
  }
}
