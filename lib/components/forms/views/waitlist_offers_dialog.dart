import 'package:fstapp/widgets/app_dialog.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import '../../../services/time_helper.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import '../../eshop/db_orders.dart';
import 'package:flutter/material.dart';
import '../../eshop/models/order_model.dart';
import '../models/form_model.dart';
import '../models/form_capacity_model.dart';
import '../waitlist_commands.dart';
import '../waitlist_strings.dart';

class WaitlistCapacitySummary extends StatelessWidget {
  const WaitlistCapacitySummary({super.key, required this.capacity});
  final FormCapacityModel capacity;
  @override
  Widget build(BuildContext context) => !capacity.enabled
      ? const SizedBox.shrink()
      : Text([
          '${WaitlistStrings.capacity}: ${capacity.limit}',
          '${WaitlistStrings.text('admitted')}: ${capacity.occupiedPeople}',
          '${WaitlistStrings.text('offered')}: ${capacity.offeredPlaces}',
          '${WaitlistStrings.text('waiting')}: ${capacity.waitingPeople}',
          '${WaitlistStrings.remaining}: ${capacity.remainingPublic}',
        ].join(' · '));
}

class WaitlistOffersDialog extends StatefulWidget {
  const WaitlistOffersDialog(
      {super.key,
      required this.form,
      this.orders = const [],
      this.targetOrderId,
      this.loadProposal,
      this.loadPreview,
      this.executeCommand});
  final FormModel form;
  final List<OrderModel> orders;
  final int? targetOrderId;
  final Future<Map<String, dynamic>> Function(int)? loadProposal;
  final Future<Map<String, dynamic>> Function(int)? loadPreview;
  final Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
      executeCommand;
  @override
  State<WaitlistOffersDialog> createState() => _WaitlistOffersDialogState();
}

class _WaitlistOffersDialogState extends State<WaitlistOffersDialog> {
  late final _commands = WaitlistCommands();
  final _counts = <int, TextEditingController>{};
  Map<String, dynamic>? _proposal;
  Map<String, dynamic>? _preview;
  List<OrderModel> _orders = [];
  DateTime? _expiresAt;
  String? _error;
  bool _busy = true;
  bool _sent = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _counts.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        (widget.loadProposal ?? _commands.proposal)(widget.form.id!),
        (widget.loadPreview ?? _commands.preview)(widget.form.id!),
        if (widget.form.link != null)
          DbOrders.getAllOrdersBundle(formLink: widget.form.link),
      ]);
      final proposal = results[0] as Map<String, dynamic>;
      _preview = results[1] as Map<String, dynamic>;
      _orders = results.length > 2
          ? (results[2] as ReservationsBundle).orders
          : widget.orders;
      if (!mounted) return;
      for (final c in _counts.values) {
        c.dispose();
      }
      _counts.clear();
      for (final order in _orders.where((o) =>
          o.isWaitlisted &&
          o.formId == widget.form.id &&
          (widget.targetOrderId == null || o.id == widget.targetOrderId))) {
        _counts[order.id!] = TextEditingController(text: '0');
      }
      for (final row in proposal['recipients'] as List) {
        if (widget.targetOrderId != null &&
            row['orderId'] != widget.targetOrderId) continue;
        (_counts[row['orderId']] ??= TextEditingController()).text =
            row['count'].toString();
      }
      setState(() {
        _proposal = proposal;
        _expiresAt = DateTime.parse(proposal['serverTime'])
            .add(Duration(seconds: proposal['offerDurationSeconds'] ?? 0));
      });
    } catch (_) {
      if (mounted) setState(() => _error = WaitlistStrings.stale);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await (widget.executeCommand ?? _commands.command)('send', {
        'formId': widget.form.id,
        'revision': _proposal!['revision'],
        'recipients': [
          for (final e in _counts.entries)
            if ((int.tryParse(e.value.text) ?? 0) > 0)
              {'orderId': e.key, 'count': int.parse(e.value.text)}
        ],
        'expiresAt': _expiresAt!.toUtc().toIso8601String(),
      });
      if (mounted) setState(() => _sent = true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _proposal = null;
          _error = WaitlistStrings.stale;
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _previewHtml(int orderId, int count) {
    final order = _orders.where((o) => o.id == orderId).firstOrNull;
    final escape = const HtmlEscape().convert;
    final participantCount =
        order?.waitlistSummary?.counts.values.fold<int>(0, (a, b) => a + b) ??
            count;
    final participantWord = participantCount == 1
        ? 'osobu'
        : participantCount >= 2 && participantCount <= 4
            ? 'osoby'
            : 'osob';
    final placeWord = count == 1
        ? 'místo'
        : count >= 2 && count <= 4
            ? 'místa'
            : 'míst';
    final expiry = _expiresAt == null
        ? ''
        : DateFormat('d. M. yyyy HH:mm').format(_expiresAt!.toOccasionTime());
    final vars = <String, String>{
      'order_symbol': escape(order?.orderSymbol ?? '$orderId'),
      'occasion_title': escape(_preview?['occasionTitle']?.toString() ?? ''),
      'participant_count': '$participantCount',
      'participant_phrase': '$participantCount $participantWord',
      'offered_count': '$count',
      'offered_places': '$count $placeWord',
      'offer_expires_at': escape(expiry),
      'offer_url': '#',
      'manage_waitlist_url': '#',
      'offer_button': '<a href="#">${escape(WaitlistStrings.accept)}</a>',
      'manage_waitlist_button':
          '<a href="#">${escape(WaitlistStrings.withdraw)}</a>',
    };
    String expand(String html) => html.replaceAllMapped(
        RegExp(r'\{\{\s*(\w+)\s*\}\}'), (m) => vars[m[1]] ?? m[0]!);
    final body = expand(_preview?['template']?['html']?.toString() ?? '');
    final wrapper = _preview?['wrapper']?['html']?.toString();
    final wrapped = wrapper == null
        ? body
        : expand(wrapper.replaceAll('{{content}}', body));
    final subject = expand(_preview?['template']?['subject']?.toString() ?? '');
    return '<h3>$subject</h3>$wrapped';
  }

  @override
  Widget build(BuildContext context) {
    final total =
        _counts.values.fold<int>(0, (n, c) => n + (int.tryParse(c.text) ?? 0));
    final capacity = _proposal == null
        ? null
        : FormCapacityModel.fromJson(
            Map<String, dynamic>.from(_proposal!['capacity']));
    return AppAlertDialog(
      dismissible: !_busy,
      onClose: () => Navigator.pop(context, _sent),
      title: Text(WaitlistStrings.send),
      content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                if (_busy) const LinearProgressIndicator(),
                if (_error != null)
                  Text(_error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                if (_sent) Text(WaitlistStrings.queued),
                if (!_sent && capacity != null) ...[
                  Text(WaitlistStrings.offerReviewExplanation),
                  WaitlistCapacitySummary(capacity: capacity),
                  if (!capacity.canSendOffers)
                    Text(
                        WaitlistStrings.text(capacity.blockedReason ?? 'full')),
                  for (final row in _counts.entries)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: TextField(
                          controller: row.value,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                              labelText:
                                  '${_orders.where((o) => o.id == row.key).firstOrNull?.toBasicString() ?? row.key} · ${WaitlistStrings.count}'),
                          onChanged: (_) => setState(() {}),
                        )),
                  Text(
                      '${WaitlistStrings.count}: $total / ${capacity.offerablePlaces}'),
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              final date = await showDatePicker(
                                  context: context,
                                  initialDate: _expiresAt!.toOccasionTime(),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 3650)));
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                      _expiresAt!.toOccasionTime()));
                              if (time != null && mounted)
                                setState(() => _expiresAt = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        time.hour,
                                        time.minute)
                                    .toUtcFromOccasionTime());
                            },
                      child: Text(
                          '${WaitlistStrings.expiresAt}: ${_expiresAt == null ? '' : DateFormat('d. M. yyyy HH:mm').format(_expiresAt!.toOccasionTime())}')),
                  const Divider(),
                  Text(WaitlistStrings.text('emailPreview')),
                  for (final e in _counts.entries
                      .where((e) => (int.tryParse(e.value.text) ?? 0) > 0))
                    ExpansionTile(
                      title: Text(_orders
                              .where((o) => o.id == e.key)
                              .firstOrNull
                              ?.orderSymbol ??
                          e.key.toString()),
                      children: [
                        HtmlWidget(_previewHtml(e.key, int.parse(e.value.text)),
                            onTapUrl: (_) => true)
                      ],
                    ),
                ],
              ]))),
      actions: [
        if (!_sent && _proposal == null)
          TextButton(
              onPressed: _busy ? null : _load,
              child: Text(WaitlistStrings.refresh)),
        if (!_sent && _proposal != null)
          FilledButton(
              onPressed: !_busy &&
                      capacity!.canSendOffers &&
                      total > 0 &&
                      total <= capacity.offerablePlaces &&
                      _counts.values
                          .every((c) => (int.tryParse(c.text) ?? -1) >= 0)
                  ? _send
                  : null,
              child: Text(widget.targetOrderId == null
                  ? WaitlistStrings.send
                  : WaitlistStrings.offerPlace)),
      ],
    );
  }
}
