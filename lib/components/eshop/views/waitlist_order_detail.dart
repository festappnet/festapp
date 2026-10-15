import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../services/time_helper.dart';
import '../../_shared/common_strings.dart';
import '../../../data_services/rights_service.dart';
import '../../../services/dialog_helper.dart';
import '../../forms/waitlist_commands.dart';
import '../../forms/waitlist_strings.dart';
import '../../forms/services/admin_offer_form_link.dart';
import '../../forms/models/form_model.dart';
import '../../forms/views/waitlist_offers_dialog.dart';
import '../models/waitlist_summary_model.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';

class WaitlistOrderDetail extends StatefulWidget {
  const WaitlistOrderDetail({
    super.key,
    required this.order,
    this.loadDetail,
    this.executeCommand,
    this.onChanged,
    this.offerDialogBuilder,
    this.openOfferForm,
  });
  final OrderModel order;
  final Future<void> Function(String offerId)? openOfferForm;
  final Future<Map<String, dynamic>> Function(int)? loadDetail;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
      executeCommand;
  final Future<void> Function()? onChanged;
  final Widget Function(FormModel, List<OrderModel>)? offerDialogBuilder;
  @override
  State<WaitlistOrderDetail> createState() => _WaitlistOrderDetailState();
}

class _WaitlistOrderDetailState extends State<WaitlistOrderDetail> {
  late final _commands = WaitlistCommands();
  final _selected = <int>{};
  Map<String, dynamic>? _detail;
  String? _error;
  bool _busy = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final detail = await (widget.loadDetail ?? _commands.detail)(
        widget.order.id!,
      );
      if (mounted) {
        setState(() {
          _detail = detail;
          if (detail['waitlistSummary'] case final Map summary) {
            final parsed = WaitlistSummaryModel.fromJson(
              Map<String, dynamic>.from(summary),
            );
            widget.order.waitlistSummary = parsed;
            widget.order.active = parsed.isActive;
            widget.order.allowedActions = parsed.allowedActions;
          }
          _selected.clear();
          _error = null;
          final eligible =
              (detail['tickets'] as List? ?? []).where(_isSelectable).toList();
          if (eligible.length == 1) {
            _selected.add(eligible.single['id'] as int);
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = WaitlistStrings.invalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _notifyParent() async {
    try {
      await widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _error = WaitlistStrings.refreshAfterMutation);
      }
    }
  }

  Future<void> _withdraw() async {
    if (!RightsService.isEditorOrder() ||
        _selected.isEmpty ||
        _busy ||
        _error != null) {
      return;
    }
    final title = _selected.length == 1
        ? WaitlistStrings.withdrawTitle
        : WaitlistStrings.withdrawSelectedTitle;
    if (!await DialogHelper.showConfirmationDialog(
      context,
      title,
      '${WaitlistStrings.withdrawExplanation}\n${WaitlistStrings.count}: ${_selected.length}',
      confirmButtonMessage: WaitlistStrings.text('adminWithdraw'),
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await (widget.executeCommand ?? _commands.command)('withdraw', {
        'orderId': widget.order.id,
        'ticketIds': _selected.toList(),
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = WaitlistStrings.stale;
          _busy = false;
        });
      }
      return;
    }
    // The mutation succeeded. Refresh failures must not turn it into a failed command.
    _selected.clear();
    await _load();
    await _notifyParent();
  }

  bool get _hasEligibleTickets =>
      (_detail?['tickets'] as List? ?? []).any(_isSelectable);
  bool get _hasWaitingTickets => (_detail?['tickets'] as List? ?? []).any(
        (ticket) => ticket['lifecycle'] == 'waiting',
      );

  bool get _canOffer =>
      !_busy &&
      _error == null &&
      _hasWaitingTickets &&
      RightsService.isEditorOrder() &&
      widget.order.isWaitlisted &&
      (widget.order.allowedActions == null || widget.order.allows('offer')) &&
      widget.order.form?.waitlistEnabled == true &&
      _detail?['capacity']?['canSendOffers'] == true;

  Future<void> _offer() async {
    if (!_canOffer) return;
    final form = widget.order.form!;
    await showDialog(
      context: context,
      builder: (_) =>
          widget.offerDialogBuilder?.call(form, [widget.order]) ??
          WaitlistOffersDialog(
            form: form,
            orders: [widget.order],
            targetOrderId: widget.order.id,
          ),
    );
    if (!mounted) return;
    await _load();
    await _notifyParent();
  }

  bool _isSelectable(dynamic ticket) => const {
        'waiting',
        'offered',
        'offer_expired',
        'offer_declined',
        'offer_cancelled',
      }.contains(ticket['lifecycle']);

  String _ticketLabel(dynamic ticket, int index) {
    final name = ticket['displayName']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final count = (_detail?['tickets'] as List? ?? []).length;
    return count == 1
        ? OrdersStrings.itemSingular
        : '${OrdersStrings.itemSingular} ${index + 1}';
  }

  String _ticketStatus(dynamic ticket) => WaitlistStrings.text(
        switch (ticket['lifecycle'] as String) {
          'waiting' => 'waitingForPlace',
          'offered' => 'awaitingOfferAcceptance',
          final String lifecycle => lifecycle,
        },
      );

  String _slotLabel(dynamic slot) {
    final tickets = _detail?['tickets'] as List? ?? [];
    final index = tickets.indexWhere(
      (ticket) => ticket['id'] == slot['ticketId'],
    );
    return index < 0
        ? OrdersStrings.itemSingular
        : _ticketLabel(tickets[index], index);
  }

  bool _offerIsPending(dynamic offer) {
    final now = DateTime.tryParse(
      _detail?['capacity']?['serverTime']?.toString() ?? '',
    );
    final expires = DateTime.tryParse(offer['expires_at']?.toString() ?? '');
    return now != null &&
        expires != null &&
        expires.isAfter(now) &&
        (offer['slots'] as List).any((s) => s['outcome'] == 'pending');
  }

  Future<void> _openOffer(dynamic offer) async {
    if (_busy ||
        _error != null ||
        !RightsService.isEditorOrder() ||
        !_offerIsPending(offer)) {
      return;
    }
    setState(() => _busy = true);
    try {
      if (widget.openOfferForm != null) {
        await widget.openOfferForm!(offer['id'] as String);
      } else {
        if (!await AdminOfferFormLink.open(
              offerId: offer['id'] as String,
            )) {
          throw StateError('Offer form could not be opened');
        }
      }
    } catch (_) {
      if (mounted) setState(() => _error = WaitlistStrings.invalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    await _load();
    await _notifyParent();
  }

  Widget _withdrawalAction() => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OutlinedButton(
              onPressed: !_busy && _error == null && _selected.isNotEmpty
                  ? _withdraw
                  : null,
              child: Text(WaitlistStrings.text('adminWithdraw')),
            ),
            if (_selected.isEmpty && !_busy && _error == null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  WaitlistStrings.text('withdrawSelection'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      );

  Widget _offerContext(dynamic offer, {required bool active}) {
    final theme = Theme.of(context);
    final expires = DateTime.tryParse(offer['expires_at']?.toString() ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (active)
            Text(
              WaitlistStrings.text('activeOffer'),
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (expires != null) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              children: [
                Text(
                  '${WaitlistStrings.expiresAt}:',
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  DateFormat('d. M. yyyy HH:mm')
                      .format(expires.toOccasionTime()),
                  maxLines: 1,
                  softWrap: false,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ],
          if (!active || (_detail?['tickets'] as List? ?? []).length > 1)
            for (final slot in offer['slots'])
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${_slotLabel(slot)} · ${WaitlistStrings.text(slot['outcome'] == 'pending' && !active ? 'expired' : slot['outcome'])}',
                ),
              ),
          if (active && RightsService.isEditorOrder()) ...[
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  _busy || _error != null ? null : () => _openOffer(offer),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  WaitlistStrings.text('completeRegistration'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              WaitlistStrings.text('openOfferFormHelp'),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tickets = _detail?['tickets'] as List? ?? [];
    final offers = _detail?['offers'] as List? ?? [];
    final activeOffers = offers.where(_offerIsPending).toList();
    final history = offers.where((offer) => !_offerIsPending(offer)).toList();
    final editor = RightsService.isEditorOrder();
    final canManage =
        editor && widget.order.isWaitlisted && _hasEligibleTickets;
    final multiple = tickets.where(_isSelectable).length > 1;
    return AppAlertDialog(
      onClose: () => Navigator.pop(context),
      title: Text(
        '${WaitlistStrings.detail} ${widget.order.orderSymbol ?? ''}',
      ),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              if (multiple && editor)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(WaitlistStrings.text('detailSelection')),
                ),
              if (!_busy && _error == null && tickets.isEmpty)
                Text(WaitlistStrings.text('emptyDetail')),
              if (tickets.isNotEmpty)
                Material(
                  color: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final entry in tickets.indexed)
                          if (multiple && editor && _isSelectable(entry.$2))
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              value: _selected.contains(entry.$2['id']),
                              title: Text(_ticketLabel(entry.$2, entry.$1)),
                              subtitle: Text(
                                _ticketStatus(entry.$2),
                              ),
                              onChanged: _busy || _error != null
                                  ? null
                                  : (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(entry.$2['id']);
                                        } else {
                                          _selected.remove(entry.$2['id']);
                                        }
                                      }),
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _ticketLabel(entry.$2, entry.$1),
                                    style: theme.textTheme.titleLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _ticketStatus(entry.$2),
                                    style: theme.textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            ),
                        if (activeOffers.isNotEmpty) const Divider(height: 24),
                        for (final offer in activeOffers)
                          _offerContext(offer, active: true),
                        if (canManage && _hasWaitingTickets) ...[
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: _canOffer ? _offer : null,
                            child: Text(WaitlistStrings.offerPlace),
                          ),
                          if (!_busy &&
                              _detail?['capacity']?['canSendOffers'] != true)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _detail?['capacity']?['blockedReason'] ==
                                        'WAITLIST_NOT_AVAILABLE'
                                    ? WaitlistStrings.text(
                                        'WAITLIST_NOT_AVAILABLE',
                                      )
                                    : WaitlistStrings.full,
                              ),
                            ),
                        ],
                        if (canManage) _withdrawalAction(),
                      ],
                    ),
                  ),
                ),
              if (_error != null)
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    TextButton.icon(
                      onPressed: _busy ? null : _refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: Text(CommonStrings.retry),
                    ),
                  ],
                ),
              if (history.isNotEmpty)
                ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  title: Text(WaitlistStrings.text('offerHistory')),
                  children: [
                    for (final offer in history)
                      _offerContext(offer, active: false),
                  ],
                ),
              if ((_detail?['linkedOrders'] as List? ?? []).isNotEmpty) ...[
                const Divider(height: 24),
                Text(
                  WaitlistStrings.linkedOrders,
                  style: theme.textTheme.titleMedium,
                ),
                for (final order in _detail?['linkedOrders'] ?? [])
                  Text(
                    '${order['orderSymbol']} · ${OrderModel.stateToLocale(order['state'])}',
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: const [],
    );
  }
}
