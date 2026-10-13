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
      : Wrap(spacing: 16, runSpacing: 4, children: [
          Text(WaitlistStrings.text('occupancy')
              .replaceAll('{occupied}', '${capacity.occupiedPeople}')
              .replaceAll('{capacity}', '${capacity.limit ?? ''}')),
          Text('${WaitlistStrings.text('waiting')}: ${capacity.waitingPeople}'),
          if (capacity.offeredPlaces > 0)
            Text('${WaitlistStrings.text('offered')}: ${capacity.offeredPlaces}'),
          Text('${WaitlistStrings.remaining}: ${capacity.offerablePlaces}'),
        ]);

}

class WaitlistOffersDialog extends StatefulWidget {
  const WaitlistOffersDialog(
      {super.key,
      required this.form,
      this.orders = const [],
      this.targetOrderId,
      this.selectedOrderIds,
      this.loadProposal,
      this.loadPreview,
      this.executeCommand});
  final FormModel form;
  final List<OrderModel> orders;
  final int? targetOrderId;
  final Set<int>? selectedOrderIds;
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
  String? get _expiryTimeZone => _preview?['timeZone'] as String?;
  String? _error;
  bool _busy = true;
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

  bool _includesOrder(int id) =>
      (widget.targetOrderId == null || id == widget.targetOrderId) &&
      (widget.selectedOrderIds == null || widget.selectedOrderIds!.contains(id));

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
          _includesOrder(o.id!))) {
        _counts[order.id!] = TextEditingController(text: '0');
      }
      for (final row in proposal['recipients'] as List) {
        if (!_includesOrder(row['orderId'] as int)) continue;
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
    final recipients = [
      for (final e in _counts.entries)
        if ((int.tryParse(e.value.text) ?? 0) > 0)
          {'orderId': e.key, 'count': int.parse(e.value.text)}
    ];
    try {
      final result = await (widget.executeCommand ?? _commands.command)('send', {
        'formId': widget.form.id,
        'revision': _proposal!['revision'],
        'recipients': recipients,
        'expiresAt': _expiresAt!.toUtc().toIso8601String(),
      });
      if (result['code'] != 200) throw WaitlistCommandException(result);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(SnackBar(content: Text(WaitlistStrings.text(
          recipients.length == 1 ? 'offerSending' : 'offersSending'))));
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
        : DateFormat('d. M. yyyy HH:mm')
            .format(_expiresAt!.toOccasionTime(_expiryTimeZone))
            .replaceAll(RegExp(r'\s'), '\u00a0');
    final toneSubstitutions = _preview?['toneSubstitutions'];
    String previewLabel(String key, String fallback) =>
        toneSubstitutions is Map && toneSubstitutions[key] is String
            ? escape(toneSubstitutions[key] as String)
            : escape(fallback);
    final vars = <String, String>{
      for (final key in const [
        'waitlist_confirmation_heading',
        'waitlist_confirmation_explanation',
        'waitlist_offer_heading',
        'waitlist_offer_instructions',
      ])
        if (toneSubstitutions is Map && toneSubstitutions[key] is String)
          key: escape(toneSubstitutions[key] as String),
      'order_symbol': escape(order?.orderSymbol ?? '$orderId'),
      'occasion_title': escape(_preview?['occasionTitle']?.toString() ?? ''),
      'participant_count': '$participantCount',
      'participant_phrase': '$participantCount $participantWord',
      'offered_count': '$count',
      'offered_places': '$count $placeWord',
      'offer_expires_at': escape(expiry),
      'offer_url': '#',
      'manage_waitlist_url': '#',
      'offer_button': '<a href="#">${previewLabel(count == 1 ? 'waitlist_offer_button_single' : 'waitlist_offer_button_multiple', WaitlistStrings.accept)}</a>',
      'manage_waitlist_button':
          '<a href="#">${previewLabel('waitlist_manage_button_label', WaitlistStrings.withdraw)}</a>',
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
      onClose: () => Navigator.pop(context, false),
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
                if (capacity != null) ...[
                  Text(WaitlistStrings.offerReviewExplanation),
                  const SizedBox(height: 12),
                  WaitlistCapacitySummary(capacity: capacity),
                  const SizedBox(height: 8),
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
                              final pickerNow = DateTime.now().toUtc().toOccasionTime(_expiryTimeZone);
                              final date = await showDatePicker(
                                  context: context,
                                  initialDate: _expiresAt!.toOccasionTime(_expiryTimeZone),
                                  firstDate: pickerNow,
                                  lastDate: pickerNow
                                      .add(const Duration(days: 3650)));
                              if (date == null || !context.mounted) return;
                              final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                      _expiresAt!.toOccasionTime(_expiryTimeZone)));
                              if (time != null && mounted) {
                                setState(() => _expiresAt = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        time.hour,
                                        time.minute)
                                    .toUtcFromOccasionTime(_expiryTimeZone));
                              }
                            },
                      child: Text(
                          '${WaitlistStrings.expiresAt}: ${_expiresAt == null ? '' : DateFormat('d. M. yyyy HH:mm').format(_expiresAt!.toOccasionTime(_expiryTimeZone))}')),
                  const Divider(),
                  Text(WaitlistStrings.text('emailPreview')),
                  for (final e in _counts.entries
                      .where((e) => (int.tryParse(e.value.text) ?? 0) > 0))
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(top: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border.all(color: Theme.of(context).dividerColor),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_orders.where((o) => o.id == e.key).firstOrNull?.toBasicString() ?? '',
                              style: Theme.of(context).textTheme.titleSmall),
                          const Divider(height: 24),
                          HtmlWidget(_previewHtml(e.key, int.parse(e.value.text)),
                              onTapUrl: (_) => true),
                        ],
                      ),
                    ),
                ],
              ]))),
      actions: [
        if (_proposal == null)
          TextButton(
              onPressed: _busy ? null : _load,
              child: Text(WaitlistStrings.refresh)),
        if (_proposal != null)
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
