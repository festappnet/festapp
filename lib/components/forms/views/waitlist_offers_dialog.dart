import 'package:fstapp/widgets/app_dialog.dart';

import 'dart:convert';

import 'package:intl/intl.dart';

import '../../../services/time_helper.dart';

import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

import '../../eshop/db_orders.dart';

import 'package:flutter/material.dart';

import '../../eshop/models/order_model.dart';
import '../models/form_bundle.dart';
import 'package:festapp_core/forms.dart';

import '../waitlist_commands.dart';
import '../waitlist_strings.dart';

class WaitlistCapacitySummary extends StatelessWidget {
  const WaitlistCapacitySummary({super.key, required this.capacity});
  final FormCapacityModel capacity;
  @override
  Widget build(BuildContext context) => !capacity.enabled
      ? const SizedBox.shrink()
      : Wrap(
          spacing: 16,
          runSpacing: 4,
          children: [
            Text(
              WaitlistStrings.text('occupancy')
                  .replaceAll('{occupied}', '${capacity.occupiedPlaces}')
                  .replaceAll('{capacity}', '${capacity.limit ?? ''}'),
            ),
            Text(
              '${WaitlistStrings.text('waiting')}: ${capacity.waitingPeople}',
            ),
            if (capacity.offeredPlaces > 0)
              Text(
                '${WaitlistStrings.text('offered')}: ${capacity.offeredPlaces}',
              ),
            Text('${WaitlistStrings.remaining}: ${capacity.offerablePlaces}'),
          ],
        );
}

class WaitlistOffersDialog extends StatefulWidget {
  const WaitlistOffersDialog({
    super.key,
    required this.form,
    this.orders = const [],
    this.targetOrderId,
    this.selectedOrderIds,
    this.loadProposal,
    this.loadPreview,
    this.executeCommand,
  });
  final FormBundle form;
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
  final _counts = <int, int>{};
  final _eligibleCounts = <int, int>{};
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

  bool _includesOrder(int id) =>
      (widget.targetOrderId == null || id == widget.targetOrderId) &&
      (widget.selectedOrderIds == null ||
          widget.selectedOrderIds!.contains(id));

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final results = await Future.wait([
        (widget.loadProposal ?? _commands.proposal)(widget.form.definition.id!),
        (widget.loadPreview ?? _commands.preview)(widget.form.definition.id!),
        if (widget.form.definition.link != null)
          DbOrders.getAllOrdersBundle(formLink: widget.form.definition.link),
      ]);
      final proposal = results[0] as Map<String, dynamic>;
      _preview = results[1] as Map<String, dynamic>;
      _orders = results.length > 2
          ? (results[2] as ReservationsBundle).orders
          : widget.orders;
      if (!mounted) return;
      _counts.clear();
      _eligibleCounts.clear();
      // Limits come from the same revision as the proposal, never from the
      // suggested count (which may have been reduced by available capacity).
      for (final row in proposal['recipients'] as List) {
        final id = row['orderId'] as int;
        final limit = row['waitingCount'] as int? ?? 0;
        if (!_includesOrder(id) || limit <= 0) continue;
        _eligibleCounts[id] = limit;
        _counts[id] = 0;
      }
      for (final row in proposal['recipients'] as List) {
        final id = row['orderId'] as int;
        if (!_includesOrder(id)) continue;
        final count = row['count'] as int;
        if (!_eligibleCounts.containsKey(id) ||
            count < 0 ||
            count > _eligibleCounts[id]!) {
          throw const FormatException('Invalid offer proposal');
        }
        _counts[id] = count;
      }
      setState(() {
        _proposal = proposal;
        _error = null;
        _expiresAt = DateTime.parse(proposal['serverTime'])
            .add(Duration(seconds: proposal['offerDurationSeconds'] ?? 0));
      });
    } catch (_) {
      if (mounted) setState(() => _error = WaitlistStrings.stale);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  int get _total => _counts.values.fold(0, (sum, count) => sum + count);

  bool _canSend(FormCapacityModel capacity) =>
      !_busy &&
      capacity.canSendOffers &&
      _total > 0 &&
      _total <= capacity.offerablePlaces &&
      _counts.entries.every(
        (e) => e.value >= 0 && e.value <= (_eligibleCounts[e.key] ?? 0),
      );

  Future<void> _send() async {
    if (_proposal == null ||
        !_canSend(
          FormCapacityModel.fromJson(
            Map<String, dynamic>.from(_proposal!['capacity']),
          ),
        )) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final recipients = [
      for (final e in _counts.entries)
        if (e.value > 0) {'orderId': e.key, 'count': e.value},
    ];
    try {
      final result = await (widget.executeCommand ?? _commands.command)(
        'send',
        {
          'formId': widget.form.definition.id,
          'revision': _proposal!['revision'],
          'recipients': recipients,
          'expiresAt': _expiresAt!.toUtc().toIso8601String(),
        },
      );
      if (result['code'] != 200) throw WaitlistCommandException(result);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.pop(context, true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            WaitlistStrings.text(
              recipients.length == 1 ? 'offerSending' : 'offersSending',
            ),
          ),
        ),
      );
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
      ])
        if (toneSubstitutions is Map && toneSubstitutions[key] is String)
          key: escape(toneSubstitutions[key] as String),
      'waitlist_offer_instructions': previewLabel(
        participantCount == 1 &&
                count == 1 &&
                toneSubstitutions is Map &&
                toneSubstitutions['waitlist_offer_instructions_single']
                    is String
            ? 'waitlist_offer_instructions_single'
            : 'waitlist_offer_instructions',
        '',
      ),
      'order_symbol': escape(order?.orderSymbol ?? '$orderId'),
      'occasion_title': escape(_preview?['occasionTitle']?.toString() ?? ''),
      'participant_count': '$participantCount',
      'participant_phrase': '$participantCount $participantWord',
      'offered_count': '$count',
      'offered_places': '$count $placeWord',
      'offer_expires_at': escape(expiry),
      'offer_url': '#',
      'manage_waitlist_url': '#',
      'offer_button':
          '<a href="#">${previewLabel(count == 1 ? 'waitlist_offer_button_single' : 'waitlist_offer_button_multiple', WaitlistStrings.accept)}</a>',
      'manage_waitlist_button':
          '<a href="#">${previewLabel('waitlist_manage_button_label', WaitlistStrings.withdraw)}</a>',
    };
    String expand(String html) => html.replaceAllMapped(
          RegExp(r'\{\{\s*(\w+)\s*\}\}'),
          (m) => vars[m[1]] ?? m[0]!,
        );
    final body = expand(
      _preview?['instructionsTemplateHtml']?.toString() ??
          _preview?['template']?['html']?.toString() ??
          '',
    );
    final wrapper = _preview?['wrapper']?['html']?.toString();
    final wrapped = wrapper == null
        ? body
        : expand(wrapper.replaceAll('{{content}}', body));
    final subject = expand(_preview?['template']?['subject']?.toString() ?? '');
    return '<h3>$subject</h3>$wrapped';
  }

  Widget _recipient(int id, FormCapacityModel capacity) {
    final order = _orders.where((o) => o.id == id).firstOrNull;
    final name = order?.toCustomerData().trim() ?? '';
    final email = order?.data?['email'] as String? ?? '';
    final count = _counts[id]!;
    final limit = _eligibleCounts[id]!;
    final selected = count > 0;
    final canIncrease = !_busy &&
        count < limit &&
        _total < capacity.offerablePlaces &&
        capacity.canSendOffers;
    final label = name.isNotEmpty ? name : order?.orderSymbol ?? '#$id';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                key: ValueKey('offer-select-$id'),
                value: selected,
                semanticLabel: label,
                onChanged: !_busy && (selected || canIncrease)
                    ? (value) =>
                        setState(() => _counts[id] = value == true ? 1 : 0)
                    : null,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: theme.textTheme.titleMedium),
                      if (email.isNotEmpty && email != name)
                        Text(email, style: theme.textTheme.bodyMedium),
                      if (order?.orderSymbol != null &&
                          order!.orderSymbol != label)
                        Text(
                          order.orderSymbol!,
                          style: theme.textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 52, top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (limit == 1)
                  Text(
                    WaitlistStrings.text('singleOfferPlace'),
                    style: theme.textTheme.titleSmall,
                  )
                else ...[
                  Text(
                    WaitlistStrings.text('offerCountLimit')
                        .replaceAll('{max}', '$limit'),
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton.outlined(
                        key: ValueKey('offer-decrease-$id'),
                        tooltip: WaitlistStrings.text('fewerPlaces'),
                        onPressed: !_busy && count > 1
                            ? () => setState(() => _counts[id] = count - 1)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      SizedBox(
                        width: 48,
                        child: Semantics(
                          liveRegion: true,
                          label: '${WaitlistStrings.count}: $count',
                          child: Text(
                            '$count',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        key: ValueKey('offer-increase-$id'),
                        tooltip: WaitlistStrings.text('morePlaces'),
                        onPressed: selected && canIncrease
                            ? () => setState(() => _counts[id] = count + 1)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = _total;
    final capacity = _proposal == null
        ? null
        : FormCapacityModel.fromJson(
            Map<String, dynamic>.from(_proposal!['capacity']),
          );
    return AppAlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (capacity != null) ...[
                Text(WaitlistStrings.offerReviewExplanation),
                const SizedBox(height: 12),
                WaitlistCapacitySummary(capacity: capacity),
                const SizedBox(height: 8),
                if (!capacity.canSendOffers)
                  Text(WaitlistStrings.text(capacity.blockedReason ?? 'full')),
                const Divider(height: 24),
                Text(
                  WaitlistStrings.text('offerRecipients'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (final id in _counts.keys) _recipient(id, capacity),
                const Divider(height: 24),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    WaitlistStrings.text('offerSelectionSummary')
                        .replaceAll('{count}', '$total')
                        .replaceAll(
                          '{available}',
                          '${capacity.offerablePlaces}',
                        ),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (total == 0)
                  Text(WaitlistStrings.text('selectOfferRecipient')),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          final pickerNow = DateTime.now()
                              .toUtc()
                              .toOccasionTime(_expiryTimeZone);
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _expiresAt!.toOccasionTime(
                              _expiryTimeZone,
                            ),
                            firstDate: pickerNow,
                            lastDate: pickerNow.add(const Duration(days: 3650)),
                          );
                          if (date == null || !context.mounted) return;
                          final time = await showTimePicker(
                            context: context,
                            initialTime: TimeOfDay.fromDateTime(
                              _expiresAt!.toOccasionTime(_expiryTimeZone),
                            ),
                          );
                          if (time != null && mounted) {
                            setState(
                              () => _expiresAt = DateTime(
                                date.year,
                                date.month,
                                date.day,
                                time.hour,
                                time.minute,
                              ).toUtcFromOccasionTime(_expiryTimeZone),
                            );
                          }
                        },
                  child: Text(
                    '${WaitlistStrings.expiresAt}: ${_expiresAt == null ? '' : DateFormat('d. M. yyyy HH:mm').format(_expiresAt!.toOccasionTime(_expiryTimeZone))}',
                  ),
                ),
                const Divider(),
                Text(WaitlistStrings.text('emailPreview')),
                for (final e in _counts.entries.where((e) => e.value > 0))
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
                        Text(
                          _orders
                                  .where((o) => o.id == e.key)
                                  .firstOrNull
                                  ?.toBasicString() ??
                              '',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Divider(height: 24),
                        HtmlWidget(
                          _previewHtml(e.key, e.value),
                          onTapUrl: (_) => true,
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_proposal == null)
          TextButton(
            onPressed: _busy ? null : _load,
            child: Text(WaitlistStrings.refresh),
          ),
        if (_proposal != null)
          FilledButton(
            onPressed: _canSend(capacity!) ? _send : null,
            child: Text(
              widget.targetOrderId == null
                  ? WaitlistStrings.send
                  : WaitlistStrings.offerPlace,
            ),
          ),
      ],
    );
  }
}
