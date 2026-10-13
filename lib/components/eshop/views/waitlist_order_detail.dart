import 'package:flutter/material.dart';
import '../../_shared/common_strings.dart';
import '../../../data_services/rights_service.dart';
import '../../../services/dialog_helper.dart';
import '../../forms/waitlist_commands.dart';
import '../../forms/waitlist_strings.dart';
import '../../forms/views/form_page.dart';
import '../models/order_model.dart';

class WaitlistOrderDetail extends StatefulWidget {
  const WaitlistOrderDetail({super.key, required this.order});
  final OrderModel order;
  @override
  State<WaitlistOrderDetail> createState() => _WaitlistOrderDetailState();
}

class _WaitlistOrderDetailState extends State<WaitlistOrderDetail> {
  final _commands = WaitlistCommands();
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
      final detail = await _commands.detail(widget.order.id!);
      if (mounted)
        setState(() {
          _detail = detail;
          _selected.clear();
        });
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
      if (mounted)
        setState(() {
          _error = WaitlistStrings.stale;
          _busy = false;
        });
    }
  }

  bool _selectionBelongsTo(dynamic offer) =>
      _selected.isNotEmpty &&
      _selected.every((id) => (offer['slots'] as List)
          .any((s) => s['ticketId'] == id && s['outcome'] == 'pending'));

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
  Widget build(BuildContext context) => AlertDialog(
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
                  for (final p in _detail?['tickets'] ?? [])
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(p['id']),
                      title: Text((p['answers']?['fields'] as List? ?? [])
                          .expand((f) => (f as Map).values)
                          .join(' · ')),
                      subtitle: Text(
                          '${WaitlistStrings.text(p['lifecycle'])} · ${p['registered_at']} · ${p['queue_at']}'),
                      onChanged: !_busy &&
                              RightsService.isEditorOrder() &&
                              !['admitted', 'withdrawn', 'cancelled']
                                  .contains(p['lifecycle'])
                          ? (v) => setState(() {
                                if (v == true) {
                                  _selected.add(p['id']);
                                } else {
                                  _selected.remove(p['id']);
                                }
                              })
                          : null,
                    ),
                  if (RightsService.isEditorOrder() &&
                      widget.order.isWaitlisted)
                    TextButton(
                        onPressed: _busy || _selected.isEmpty
                            ? null
                            : () => _resolve('withdraw'),
                        child: Text(WaitlistStrings.withdraw)),
                  Text(WaitlistStrings.offers,
                      style: Theme.of(context).textTheme.titleMedium),
                  Text(WaitlistStrings.text('selectionExplanation')),
                  for (final offer in _detail?['offers'] ?? [])
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  '${WaitlistStrings.expiresAt}: ${DateTime.tryParse(offer['expires_at'])?.toLocal()}'),
                              for (final slot in offer['slots'])
                                Text(
                                    '${slot['ticketId']} · ${WaitlistStrings.text(slot['outcome'] == 'pending' && !_offerIsPending(offer) ? 'expired' : slot['outcome'])}'),
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
                                              await Navigator.of(context).push(
                                                  MaterialPageRoute(
                                                      builder: (_) => FormPage(
                                                          formLink: bundle[
                                                                      'form']
                                                                  ['link'] ??
                                                              widget.order.form
                                                                  ?.link,
                                                          offerId:
                                                              offer['id'])));
                                              await _load();
                                            },
                                      child: Text(WaitlistStrings.accept)),
                                  TextButton(
                                      onPressed: _busy ||
                                              !_selectionBelongsTo(offer)
                                          ? null
                                          : () =>
                                              _resolve('decline', offer['id']),
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
                  Text(WaitlistStrings.linkedOrders,
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_detail?['sourceOrderId'] != null)
                    Text('${_detail!['sourceOrderId']}'),
                  for (final order in _detail?['linkedOrders'] ?? [])
                    Text(
                        '${order['orderSymbol']} · ${OrderModel.stateToLocale(order['state'])}'),
                ]))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(CommonStrings.close))
        ],
      );
}
