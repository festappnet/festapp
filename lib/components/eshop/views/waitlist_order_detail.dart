import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/time_helper.dart';
import '../../../data_services/rights_service.dart';
import '../../../services/dialog_helper.dart';
import '../../forms/waitlist_commands.dart';
import '../../forms/waitlist_strings.dart';
import '../../forms/views/form_page.dart';
import '../../forms/models/form_model.dart';
import '../../forms/views/waitlist_offers_dialog.dart';
import '../models/waitlist_summary_model.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';

class WaitlistOrderDetail extends StatefulWidget {
  const WaitlistOrderDetail(
      {super.key,
      required this.order,
      this.loadDetail,
      this.executeCommand,
      this.onChanged,
      this.offerDialogBuilder});
  final OrderModel order;
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
      final detail =
          await (widget.loadDetail ?? _commands.detail)(widget.order.id!);
      if (mounted) {
        setState(() {
          _detail = detail;
          if (detail['waitlistSummary'] case final Map summary) {
            final parsed = WaitlistSummaryModel.fromJson(
                Map<String, dynamic>.from(summary));
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
      if (mounted)
        setState(() => _error = WaitlistStrings.refreshAfterMutation);
    }
  }

  Future<void> _resolve(String operation, [String? offerId]) async {
    if (!RightsService.isEditorOrder() || _selected.isEmpty || _busy) return;
    final (title, explanation, button) = switch (operation) {
      'withdraw' => (
          _selected.length == 1
              ? WaitlistStrings.withdrawTitle
              : WaitlistStrings.withdrawSelectedTitle,
          WaitlistStrings.withdrawExplanation,
          WaitlistStrings.withdraw
        ),
      'decline' => (
          WaitlistStrings.declineOfferTitle,
          WaitlistStrings.declineOfferExplanation,
          WaitlistStrings.decline
        ),
      'cancel' => (
          WaitlistStrings.cancelOfferTitle,
          WaitlistStrings.cancelOfferExplanation,
          WaitlistStrings.cancel
        ),
      _ => throw ArgumentError.value(operation),
    };
    if (!await DialogHelper.showConfirmationDialog(context, title, explanation,
        confirmButtonMessage: button)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await (widget.executeCommand ?? _commands.command)(operation, {
        'orderId': widget.order.id,
        if (offerId != null) 'offerId': offerId,
        'ticketIds': _selected.toList()
      });
    } catch (_) {
      if (mounted)
        setState(() {
          _error = WaitlistStrings.stale;
          _busy = false;
        });
      return;
    }
    // The mutation succeeded. Refresh failures must not turn it into a failed command.
    _selected.clear();
    await _load();
    await _notifyParent();
  }

  bool get _hasEligibleTickets =>
      (_detail?['tickets'] as List? ?? []).any(_isSelectable);
  bool get _canOffer =>
      !_busy &&
      _error == null &&
      _hasEligibleTickets &&
      RightsService.isEditorOrder() &&
      widget.order.isWaitlisted &&
      widget.order.form?.waitlistEnabled == true &&
      _detail?['capacity']?['canSendOffers'] == true;

  Future<void> _offer() async {
    if (!_canOffer) return;
    if (!await DialogHelper.showConfirmationDialog(
        context, WaitlistStrings.offerTitle, WaitlistStrings.offerExplanation,
        confirmButtonMessage: WaitlistStrings.offerContinue)) return;
    if (!mounted) return;
    final form = widget.order.form!;
    await showDialog(
        context: context,
        builder: (_) =>
            widget.offerDialogBuilder?.call(form, [widget.order]) ??
            WaitlistOffersDialog(
                form: form,
                orders: [widget.order],
                targetOrderId: widget.order.id));
    if (!mounted) return;
    await _load();
    await _notifyParent();
  }

  bool _selectionBelongsTo(dynamic offer) =>
      _selected.isNotEmpty &&
      _selected.every((id) => (offer['slots'] as List)
          .any((s) => s['ticketId'] == id && s['outcome'] == 'pending'));

  bool _isSelectable(dynamic ticket) => const {
        'waiting',
        'offered',
        'offer_expired',
        'offer_declined',
        'offer_cancelled'
      }.contains(ticket['lifecycle']);

  String _ticketLabel(dynamic ticket, int index) {
    final name = ticket['displayName']?.toString().trim();
    if (name != null && name.isNotEmpty) return name;
    final count = (_detail?['tickets'] as List? ?? []).length;
    return count == 1
        ? OrdersStrings.itemSingular
        : '${OrdersStrings.itemSingular} ${index + 1}';
  }

  String _slotLabel(dynamic slot) {
    final tickets = _detail?['tickets'] as List? ?? [];
    final index =
        tickets.indexWhere((ticket) => ticket['id'] == slot['ticketId']);
    return index < 0
        ? OrdersStrings.itemSingular
        : _ticketLabel(tickets[index], index);
  }

  bool _offerIsPending(dynamic offer) {
    final now = DateTime.tryParse(
        _detail?['capacity']?['serverTime']?.toString() ?? '');
    final expires = DateTime.tryParse(offer['expires_at']?.toString() ?? '');
    return now != null &&
        expires != null &&
        expires.isAfter(now) &&
        (offer['slots'] as List).any((s) => s['outcome'] == 'pending');
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
        onClose: () => Navigator.pop(context),
        title:
            Text('${WaitlistStrings.detail} ${widget.order.orderSymbol ?? ''}'),
        content: SizedBox(
            width: 650,
            child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  if (_detail?['occasionTitle'] case final String title)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(title,
                            style: Theme.of(context).textTheme.titleMedium)),
                  for (final entry
                      in (_detail?['tickets'] as List? ?? []).indexed)
                    Card(
                        child: (_detail?['tickets'] as List? ?? []).length >
                                    1 &&
                                RightsService.isEditorOrder() &&
                                _isSelectable(entry.$2)
                            ? CheckboxListTile(
                                value: _selected.contains(entry.$2['id']),
                                title: Text(_ticketLabel(entry.$2, entry.$1)),
                                subtitle: Text(WaitlistStrings.text(
                                    entry.$2['lifecycle'])),
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                          if (value == true) {
                                            _selected.add(entry.$2['id']);
                                          } else {
                                            _selected.remove(entry.$2['id']);
                                          }
                                        }))
                            : ListTile(
                                title: Text(_ticketLabel(entry.$2, entry.$1)),
                                subtitle: Text(WaitlistStrings.text(
                                    entry.$2['lifecycle'])))),
                  if (RightsService.isEditorOrder() &&
                      widget.order.isWaitlisted &&
                      _hasEligibleTickets)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(spacing: 8, runSpacing: 8, children: [
                                OutlinedButton(
                                    onPressed: _canOffer ? _offer : null,
                                    child: Text(WaitlistStrings.offerPlace)),
                                OutlinedButton(
                                    onPressed: !_busy &&
                                            _error == null &&
                                            _selected.isNotEmpty
                                        ? () => _resolve('withdraw')
                                        : null,
                                    child: Text(WaitlistStrings.withdraw)),
                              ]),
                              if (!_busy &&
                                  _detail?['capacity']?['canSendOffers'] !=
                                      true)
                                Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(_detail?['capacity']
                                                ?['blockedReason'] ==
                                            'WAITLIST_NOT_AVAILABLE'
                                        ? WaitlistStrings.text(
                                            'WAITLIST_NOT_AVAILABLE')
                                        : WaitlistStrings.full)),
                            ])),
                  if ((_detail?['offers'] as List? ?? []).isNotEmpty) ...[
                    Text(WaitlistStrings.offers,
                        style: Theme.of(context).textTheme.titleMedium),
                    if ((_detail?['offers'] as List? ?? [])
                        .any(_offerIsPending))
                      Text(WaitlistStrings.text('selectionExplanation')),
                    for (final offer in _detail?['offers'] ?? [])
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (DateTime.tryParse(
                                        offer['expires_at']?.toString() ?? '')
                                    case final DateTime expires)
                                  Text(
                                      '${WaitlistStrings.expiresAt}: ${DateFormat('d. M. yyyy HH:mm').format(expires.toOccasionTime())}'),
                                for (final slot in offer['slots'])
                                  Text(
                                      '${_slotLabel(slot)} · ${WaitlistStrings.text(slot['outcome'] == 'pending' && !_offerIsPending(offer) ? 'expired' : slot['outcome'])}'),
                                if (RightsService.isEditorOrder() &&
                                    _offerIsPending(offer))
                                  Wrap(spacing: 8, children: [
                                    TextButton(
                                        onPressed: _busy
                                            ? null
                                            : () async {
                                                final bundle = await _commands
                                                    .read(offerId: offer['id']);
                                                if (bundle['form'] == null) {
                                                  await _load();
                                                  return;
                                                }
                                                if (!context.mounted) return;
                                                await Navigator.of(context)
                                                    .push(MaterialPageRoute(
                                                        builder: (_) => FormPage(
                                                            formLink: bundle[
                                                                        'form']
                                                                    ['link'] ??
                                                                widget.order
                                                                    .form?.link,
                                                            offerId:
                                                                offer['id'])));
                                                await _load();
                                              },
                                        child: Text(WaitlistStrings.accept)),
                                    TextButton(
                                        onPressed:
                                            _busy || !_selectionBelongsTo(offer)
                                                ? null
                                                : () => _resolve(
                                                    'decline', offer['id']),
                                        child: Text(WaitlistStrings.decline)),
                                    TextButton(
                                        onPressed: _busy ||
                                                !_selectionBelongsTo(offer)
                                            ? null
                                            : () =>
                                                _resolve('cancel', offer['id']),
                                        child: Text(WaitlistStrings.cancel)),
                                  ]),
                              ])),
                  ],
                  if ((_detail?['linkedOrders'] as List? ?? []).isNotEmpty) ...[
                    Text(WaitlistStrings.linkedOrders,
                        style: Theme.of(context).textTheme.titleMedium),
                    for (final order in _detail?['linkedOrders'] ?? [])
                      Text(
                          '${order['orderSymbol']} · ${OrderModel.stateToLocale(order['state'])}'),
                  ],
                ]))),
        actions: [],
      );
}
