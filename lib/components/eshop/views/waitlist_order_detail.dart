import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../services/time_helper.dart';
import '../../../data_services/rights_service.dart';
import '../../../services/dialog_helper.dart';
import '../../forms/waitlist_commands.dart';
import '../../forms/waitlist_strings.dart';
import '../../forms/views/form_page.dart';
import '../models/order_model.dart';
import '../orders_strings.dart';

class WaitlistOrderDetail extends StatefulWidget {
  const WaitlistOrderDetail({super.key, required this.order, this.loadDetail});
  final OrderModel order;
  final Future<Map<String, dynamic>> Function(int)? loadDetail;
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

  Future<void> _resolve(String operation, [String? offerId]) async {
    if (!RightsService.isEditorOrder() || _selected.isEmpty) return;
    if (!await DialogHelper.showConfirmationDialog(
        context, WaitlistStrings.title, WaitlistStrings.confirm)) return;
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await _commands.command(operation, {
        'orderId': widget.order.id,
        if (offerId != null) 'offerId': offerId,
        'ticketIds': _selected.toList()
      });
      await _load();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = WaitlistStrings.stale;
          _busy = false;
        });
      }
    }
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
                  if (!_busy &&
                      _selected.isNotEmpty &&
                      RightsService.isEditorOrder() &&
                      widget.order.isWaitlisted)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: OutlinedButton(
                            onPressed: () => _resolve('withdraw'),
                            child: Text(WaitlistStrings.withdraw))),
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
