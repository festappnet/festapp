import 'package:festapp_core/time.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/bank_accounts/bank_account_strings.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:easy_localization/easy_localization.dart';

typedef ConfirmBankEmail = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> observation,
  int paymentInfoId, {
  bool notDuplicate,
});

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value.map((item) => Map<String, dynamic>.from(item as Map)).toList()
    : const [];

class BankSyncEmailQueue extends StatefulWidget {
  const BankSyncEmailQueue({
    super.key,
    required this.loadPage,
    required this.confirm,
    required this.readOnly,
    this.lookup,
    this.dismiss,
    this.onEmpty,
  });
  final VoidCallback? onEmpty;
  final ConfirmBankEmail confirm;
  final bool readOnly;
  final Future<Map<String, dynamic>> Function(Map<String, dynamic>? cursor)
  loadPage;
  final Future<List<Map<String, dynamic>>> Function(
    Map<String, dynamic> facts,
    String query,
  )?
  lookup;
  final Future<void> Function(Map<String, dynamic> observation, String reason)?
  dismiss;

  @override
  State<BankSyncEmailQueue> createState() => _BankSyncEmailQueueState();
}

class _BankSyncEmailQueueState extends State<BankSyncEmailQueue> {
  List<Map<String, dynamic>>? _rows;
  bool _loading = false;
  String? _feedback;
  bool _feedbackIsNotice = false;

  Map<String, dynamic>? _cursor;

  Future<void> _load({bool more = false}) async {
    setState(() => _loading = true);
    final page = await ExceptionHandler.guard<Map<String, dynamic>>(
      context,
      futureFunction: () => widget.loadPage(more ? _cursor : null),
    );
    if (!mounted) return;
    setState(() {
      if (page != null) {
        final rows = (page['items'] as List)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
        _rows = more ? [...?_rows, ...rows] : rows;
        _cursor = page['next_cursor'] == null
            ? null
            : Map<String, dynamic>.from(page['next_cursor'] as Map);
      }
      _loading = false;
    });
    if (page != null && _rows?.isEmpty == true) widget.onEmpty?.call();
  }

  Future<void> _handleConfirmOutcome(Map<String, dynamic> outcome) async {
    final action = outcome['action']?.toString();
    final paired = outcome['transaction_paired'] == true;
    setState(() {
      if (action == 'confirmed' && paired) {
        _feedback = BankAccountStrings.emailOutcomeConfirmed;
        _feedbackIsNotice = false;
      } else {
        _feedback = BankAccountStrings.emailConflict;
        _feedbackIsNotice = true;
      }
    });
    await _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Expanded(child: Text(BankAccountStrings.emailQueue)),
          IconButton(
            onPressed: _loading ? null : () => _load(),
            tooltip: CommonStrings.refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (_loading) const LinearProgressIndicator(),
      if (_feedback != null)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            _feedback!,
            style: TextStyle(
              color: _feedbackIsNotice
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      if (_rows?.isEmpty == true) Text(BankAccountStrings.emailQueueEmpty),
      for (final row in _rows ?? <Map<String, dynamic>>[])
        Builder(
          builder: (context) {
            final possibleDuplicates = _mapList(row['possible_duplicates']);
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BankEmailFacts(
                      facts: Map<String, dynamic>.from(row['facts'] as Map),
                    ),
                    if (possibleDuplicates.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      BankEmailPossibleDuplicates(
                        duplicates: possibleDuplicates,
                      ),
                    ],
                    if (row['confirmable'] == false)
                      Text(BankAccountStrings.emailConflict),
                    if (!widget.readOnly && row['confirmable'] != false)
                      TextButton(
                        onPressed: () async {
                          final outcome =
                              await showDialog<Map<String, dynamic>>(
                                context: context,
                                barrierDismissible: false,
                                builder: (_) => BankEmailConfirmationDialog(
                                  observation: row,
                                  confirm: widget.confirm,
                                  lookup: widget.lookup,
                                ),
                              );
                          if (outcome != null && mounted) {
                            await _handleConfirmOutcome(outcome);
                          }
                        },
                        child: Text(BankAccountStrings.emailConfirm),
                      ),
                    if (!widget.readOnly && widget.dismiss != null)
                      TextButton(
                        onPressed: () async {
                          final done = await showDialog<bool>(
                            context: context,
                            barrierDismissible: false,
                            builder: (context) => BankEmailDismissDialog(
                              observation: row,
                              dismiss: widget.dismiss!,
                            ),
                          );
                          if (done == true && mounted) await _load();
                        },
                        child: Text(BankAccountStrings.emailDismiss),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      if (_cursor != null)
        TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: Text(BankAccountStrings.emailLoadMore),
        ),
    ],
  );
}

class BankEmailPossibleDuplicates extends StatelessWidget {
  const BankEmailPossibleDuplicates({super.key, required this.duplicates});
  final List<Map<String, dynamic>> duplicates;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.errorContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.error.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            BankAccountStrings.emailPossibleDuplicates,
            style: TextStyle(color: colors.error, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          for (final item in duplicates) _buildDuplicateLine(context, item),
        ],
      ),
    );
  }

  Widget _buildDuplicateLine(BuildContext context, Map<String, dynamic> item) {
    if (item['restricted'] == true) {
      return Text(BankAccountStrings.emailDuplicateRestricted);
    }
    final facts = item['facts'] is Map
        ? Map<String, dynamic>.from(item['facts'] as Map)
        : const <String, dynamic>{};
    final amountCents = facts['amount_cents'];
    final currency = facts['currency']?.toString();
    final date = DateTime.tryParse(facts['date']?.toString() ?? '');
    final vs =
        facts['raw_vs']?.toString() ?? facts['payer_reference']?.toString();
    final referenceLabel = facts['raw_vs'] == null
        ? 'RF'
        : BankAccountStrings.emailVs;
    final paired = item['transaction_paired'] == true;
    final orderLabel =
        item['order_symbol']?.toString() ?? item['order_number']?.toString();
    final status = paired
        ? BankAccountStrings.emailDuplicatePaidOrder(orderLabel ?? '—')
        : BankAccountStrings.emailDuplicateUnpaired;
    final parts = <String>[
      if (date != null)
        DateFormat.yMd(context.locale.toString())
            .format(OccasionTimeContext.named('Europe/Prague').atInstant(date)),
      if (amountCents is num && currency != null)
        Utilities.formatPrice(
          context,
          amountCents.toDouble() / 100,
          currencyCode: currency,
          decimalDigits: 2,
        ),
      '$referenceLabel: ${vs ?? '—'}',
      if (facts['counter_account'] != null)
        '${facts['counter_account']} ${facts['bank_code'] ?? ''}'.trim(),
      status,
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(parts.join(' · ')),
    );
  }
}

class BankEmailFacts extends StatelessWidget {
  const BankEmailFacts({super.key, required this.facts});
  final Map<String, dynamic> facts;
  @override
  Widget build(BuildContext context) {
    final date = DateTime.tryParse(facts['date']?.toString() ?? '');
    return Text(
      [
        Utilities.formatPrice(
          context,
          (facts['amount_cents'] as num).toDouble() / 100,
          currencyCode: facts['currency'] as String,
          decimalDigits: 2,
        ),
        '${BankAccountStrings.emailVs}: ${facts['raw_vs'] ?? '—'}',
        '${BankAccountStrings.emailCounterAccount}: ${facts['counter_account'] ?? '—'} ${facts['bank_code'] ?? ''}',
        if (facts['payer_reference'] != null)
          facts['payer_reference'].toString(),
        '${BankAccountStrings.emailSender}: ${facts['sender_name'] ?? '—'}',
        if (date != null)
          DateFormat.yMd(
            context.locale.toString(),
          ).format(OccasionTimeContext.named('Europe/Prague').atInstant(date)),
        facts['message']?.toString() ?? '',
      ].join('\n'),
    );
  }
}

class BankEmailConfirmationDialog extends StatefulWidget {
  const BankEmailConfirmationDialog({
    super.key,
    required this.observation,
    required this.confirm,
    this.lookup,
  });
  final Map<String, dynamic> observation;
  final ConfirmBankEmail confirm;
  final Future<List<Map<String, dynamic>>> Function(
    Map<String, dynamic> facts,
    String query,
  )?
  lookup;
  @override
  State<BankEmailConfirmationDialog> createState() =>
      _BankEmailConfirmationDialogState();
}

class _BankEmailConfirmationDialogState
    extends State<BankEmailConfirmationDialog> {
  int? _selected;
  bool _checked = false;
  bool _notDuplicate = false;
  bool _saving = false;
  bool _searching = false;
  final _query = TextEditingController();
  List<Map>? _results;
  late List<Map<String, dynamic>> _possibleDuplicates;
  String? _duplicateReviewToken;
  String? _outcomeMessage;

  @override
  void initState() {
    super.initState();
    _possibleDuplicates = _mapList(widget.observation['possible_duplicates']);
    _duplicateReviewToken =
        widget.observation['duplicate_review_token'] as String?;
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    setState(() => _searching = true);
    final results = await ExceptionHandler.guard(
      context,
      futureFunction: () => widget.lookup!(
        Map<String, dynamic>.from(widget.observation['facts'] as Map),
        _query.text.trim(),
      ),
    );
    if (!mounted) return;
    setState(() {
      _results = results;
      _selected = null;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final candidates =
        _results ?? (widget.observation['candidates'] as List).cast<Map>();
    final needsNotDuplicate = _possibleDuplicates.isNotEmpty;
    final canSubmit =
        !_saving &&
        !_searching &&
        _checked &&
        _selected != null &&
        (!needsNotDuplicate || _notDuplicate);
    void close() {
      if (!_saving) Navigator.of(context).pop(null);
    }

    return PopScope(
      canPop: !_saving,
      child: AppAlertDialog(
        title: Text(BankAccountStrings.emailConfirm),
        dismissible: !_saving,
        onClose: close,
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BankEmailFacts(
                  facts: Map<String, dynamic>.from(
                    widget.observation['facts'] as Map,
                  ),
                ),
                if (_outcomeMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _outcomeMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_possibleDuplicates.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  BankEmailPossibleDuplicates(duplicates: _possibleDuplicates),
                ],
                const SizedBox(height: 8),
                Text(BankAccountStrings.emailLookupPayableOnly),
                if (widget.lookup != null) ...[
                  TextField(
                    controller: _query,
                    enabled: !_saving && !_searching,
                    decoration: InputDecoration(
                      labelText: BankAccountStrings.emailLookupHint,
                    ),
                    onSubmitted: (_) {
                      if (!_saving &&
                          !_searching &&
                          _query.text.trim().isNotEmpty) {
                        _search();
                      }
                    },
                  ),
                  TextButton(
                    onPressed: _saving || _searching
                        ? null
                        : () {
                            if (_query.text.trim().isNotEmpty) _search();
                          },
                    child: Text(BankAccountStrings.emailLookup),
                  ),
                ],
                if (_searching) const LinearProgressIndicator(),
                if (candidates.isEmpty)
                  Text(BankAccountStrings.emailNoCandidates),
                if (candidates.isNotEmpty)
                  RadioGroup<int>(
                    groupValue: _selected,
                    onChanged: (value) {
                      if (_saving || _searching) return;
                      setState(() => _selected = value);
                    },
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final candidate in candidates)
                          RadioListTile<int>(
                            value: (candidate['payment_info_id'] as num)
                                .toInt(),
                            enabled: !_saving && !_searching,
                            title: Text(
                              '${BankAccountStrings.emailOrder} ${candidate['order_symbol'] ?? candidate['order_number'] ?? '—'} · ${BankAccountStrings.emailOrderState(candidate['state'] as String?)}',
                            ),
                            subtitle: Text(
                              '${candidate['customer_name'] ?? ''} ${candidate['customer_email'] ?? ''}\n${Utilities.formatPrice(context, (candidate['remaining_due'] as num).toDouble(), currencyCode: (widget.observation['facts'] as Map)['currency'] as String, decimalDigits: 2)} · ${candidate['amount_matches'] == true ? BankAccountStrings.emailAmountMatches : BankAccountStrings.emailAmountDiffers}',
                            ),
                          ),
                      ],
                    ),
                  ),
                CheckboxListTile(
                  key: const ValueKey('email-attestation-checkbox'),
                  value: _checked,
                  onChanged: _saving
                      ? null
                      : (v) => setState(() => _checked = v == true),
                  title: Text(BankAccountStrings.emailAttestation),
                ),
                if (needsNotDuplicate)
                  CheckboxListTile(
                    key: const ValueKey('email-not-duplicate-checkbox'),
                    value: _notDuplicate,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _notDuplicate = v == true),
                    title: Text(BankAccountStrings.emailNotDuplicate),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : close,
            child: Text(CommonStrings.cancel),
          ),
          FilledButton(
            onPressed: !canSubmit
                ? null
                : () async {
                    setState(() {
                      _saving = true;
                      _outcomeMessage = null;
                    });
                    final result =
                        await ExceptionHandler.guard<Map<String, dynamic>>(
                          context,
                          futureFunction: () => widget.confirm(
                            {
                              ...widget.observation,
                              'duplicate_review_token': _duplicateReviewToken,
                            },
                            _selected!,
                            notDuplicate: _notDuplicate,
                          ),
                        );
                    if (!context.mounted) return;
                    if (result == null) {
                      setState(() => _saving = false);
                      return;
                    }
                    if (result['action']?.toString() == 'possible_duplicate') {
                      final returned = _mapList(result['possible_duplicates']);
                      setState(() {
                        _saving = false;
                        _possibleDuplicates = returned;
                        _duplicateReviewToken =
                            result['duplicate_review_token'] as String?;
                        _notDuplicate = false;
                        _outcomeMessage =
                            BankAccountStrings.emailOutcomePossibleDuplicate;
                      });
                      return;
                    }
                    setState(() => _saving = false);
                    Navigator.of(context).pop(result);
                  },
            child: Text(BankAccountStrings.emailConfirm),
          ),
        ],
      ),
    );
  }
}

class BankEmailDismissDialog extends StatefulWidget {
  const BankEmailDismissDialog({
    super.key,
    required this.observation,
    required this.dismiss,
  });
  final Map<String, dynamic> observation;
  final Future<void> Function(Map<String, dynamic> observation, String reason)
  dismiss;
  @override
  State<BankEmailDismissDialog> createState() => _BankEmailDismissDialogState();
}

class _BankEmailDismissDialogState extends State<BankEmailDismissDialog> {
  final _reason = TextEditingController();
  bool _saving = false;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void close() {
      if (!_saving) Navigator.of(context).pop(false);
    }

    return PopScope(
      canPop: !_saving,
      child: AppAlertDialog(
        title: Text(BankAccountStrings.emailDismiss),
        dismissible: !_saving,
        onClose: close,
        content: TextField(
          controller: _reason,
          maxLength: 240,
          enabled: !_saving,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: BankAccountStrings.emailDismissReason,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : close,
            child: Text(CommonStrings.cancel),
          ),
          FilledButton(
            onPressed: _saving || _reason.text.trim().isEmpty
                ? null
                : () async {
                    setState(() => _saving = true);
                    final done = await ExceptionHandler.guard(
                      context,
                      futureFunction: () async {
                        await widget.dismiss(
                          widget.observation,
                          _reason.text.trim(),
                        );
                        return true;
                      },
                    );
                    if (!context.mounted) return;
                    setState(() => _saving = false);
                    if (done == true) Navigator.of(context).pop(true);
                  },
            child: Text(BankAccountStrings.emailDismiss),
          ),
        ],
      ),
    );
  }
}
