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
    this.compact = false,
  });
  final bool compact;
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
  bool _loading = true;
  String? _feedback;

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
        final rows = _mapList(page['items']);
        _rows = more ? [...?_rows, ...rows] : rows;
        _cursor = page['next_cursor'] == null
            ? null
            : Map<String, dynamic>.from(page['next_cursor'] as Map);
      }
      _loading = false;
    });
  }

  Future<void> _confirm(Map<String, dynamic> row) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BankEmailConfirmationDialog(
        observation: row,
        confirm: widget.confirm,
        lookup: widget.lookup,
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _feedback =
          result['action'] == 'confirmed' &&
              result['transaction_paired'] == true
          ? BankAccountStrings.emailOutcomeConfirmed
          : BankAccountStrings.emailConflict;
    });
    await _load();
  }

  Future<void> _dismiss(Map<String, dynamic> row) async {
    final dismissed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BankEmailDismissDialog(
        dismiss: (reason) => widget.dismiss!(row, reason),
      ),
    );
    if (mounted && dismissed == true) await _load();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Widget _observationCard(Map<String, dynamic> row) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BankEmailFacts(facts: Map<String, dynamic>.from(row['facts'] as Map)),
          BankEmailPossibleDuplicates(
            duplicates: _mapList(row['possible_duplicates']),
          ),
          if (!widget.readOnly)
            TextButton(
              onPressed: () => _confirm(row),
              child: Text(BankAccountStrings.emailConfirm),
            ),
          if (!widget.readOnly && widget.dismiss != null)
            TextButton(
              onPressed: () => _dismiss(row),
              child: Text(BankAccountStrings.emailDismiss),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (widget.compact &&
        (_rows?.isEmpty == true || (_rows == null && _loading))) {
      return const SizedBox.shrink();
    }
    if (_rows == null && !_loading) {
      return TextButton(onPressed: _load, child: Text(CommonStrings.retry));
    }
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(BankAccountStrings.emailQueue)),
            IconButton(
              onPressed: _loading ? null : _load,
              tooltip: CommonStrings.refresh,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        if (_loading) const LinearProgressIndicator(),
        if (_feedback case final feedback?)
          Text(
            feedback,
            style: TextStyle(
              color: feedback == BankAccountStrings.emailConflict
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        if (_rows?.isEmpty == true) Text(BankAccountStrings.emailQueueEmpty),
        for (final row in _rows ?? []) _observationCard(row),
        if (_cursor != null)
          TextButton(
            onPressed: _loading ? null : () => _load(more: true),
            child: Text(BankAccountStrings.emailLoadMore),
          ),
      ],
    );
    return widget.compact
        ? ExpansionTile(
            key: const ValueKey('bank-pending-email-queue'),
            tilePadding: EdgeInsets.zero,
            title: Text(BankAccountStrings.emailPendingQueueExpand),
            children: [content],
          )
        : content;
  }
}

class BankEmailPossibleDuplicates extends StatelessWidget {
  const BankEmailPossibleDuplicates({
    super.key,
    required this.duplicates,
    this.onMatch,
  });
  final void Function(int transactionId)? onMatch;
  final List<Map<String, dynamic>> duplicates;

  @override
  Widget build(BuildContext context) {
    if (duplicates.isEmpty) return const SizedBox.shrink();
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
          for (final item in duplicates) ...[
            _buildDuplicateLine(context, item),
            if (onMatch != null && item['transaction_id'] is int)
              TextButton(
                onPressed: () => onMatch!(item['transaction_id'] as int),
                child: Text(
                  item['transaction_paired'] == true
                      ? BankAccountStrings.apiDuplicateSame
                      : BankAccountStrings.apiDuplicateSameAndPair,
                ),
              ),
          ],
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

class _BankEmailConfirmationDialog extends StatefulWidget {
  const _BankEmailConfirmationDialog({
    required this.observation,
    required this.confirm,
    this.lookup,
  });

  final Map<String, dynamic> observation;
  final ConfirmBankEmail confirm;
  final Future<List<Map<String, dynamic>>> Function(
    Map<String, dynamic>,
    String,
  )?
  lookup;

  @override
  State<_BankEmailConfirmationDialog> createState() => _ConfirmationState();
}

enum _ConfirmationTask { search, save }

class _ConfirmationState extends State<_BankEmailConfirmationDialog> {
  final _query = TextEditingController();
  late final _facts = Map<String, dynamic>.from(
    widget.observation['facts'] as Map,
  );
  late var _review = widget.observation;
  late var _candidates = _mapList(widget.observation['candidates']);
  _ConfirmationTask? _task;
  int? _selected;
  bool _checked = false;
  bool _notDuplicate = false;
  bool get _busy => _task != null;
  bool get _saving => _task == _ConfirmationTask.save;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.text.trim();
    if (_busy || query.isEmpty) return;
    setState(() => _task = _ConfirmationTask.search);
    final results = await ExceptionHandler.guard(
      context,
      futureFunction: () => widget.lookup!(_facts, query),
    );
    if (!mounted) return;
    setState(() {
      if (results != null) _candidates = results;
      _selected = null;
      _task = null;
    });
  }

  Future<void> _submit() async {
    setState(() => _task = _ConfirmationTask.save);
    final result = await ExceptionHandler.guard(
      context,
      futureFunction: () => widget.confirm(
        {
          ...widget.observation,
          'duplicate_review_token': _review['duplicate_review_token'],
        },
        _selected!,
        notDuplicate: _notDuplicate,
      ),
    );
    if (!mounted) return;
    setState(() {
      _task = null;
      if (result?['action'] == 'possible_duplicate') {
        _review = result!;
        _notDuplicate = false;
      }
    });
    if (result != null && result['action'] != 'possible_duplicate') {
      Navigator.of(context).pop(result);
    }
  }

  Widget _candidate(Map<String, dynamic> entry) {
    final order = entry['order_symbol'] ?? entry['order_number'] ?? '—';
    final state = BankAccountStrings.emailOrderState(entry['state'] as String?);
    final balance = Utilities.formatPrice(
      context,
      (entry['remaining_due'] as num).toDouble(),
      currencyCode: _facts['currency'] as String,
      decimalDigits: 2,
    );
    final match = entry['amount_matches'] == true
        ? BankAccountStrings.emailAmountMatches
        : BankAccountStrings.emailAmountDiffers;
    return RadioListTile<int>(
      value: (entry['payment_info_id'] as num).toInt(),
      enabled: !_busy,
      title: Text('${BankAccountStrings.emailOrder} $order · $state'),
      subtitle: Text(
        '${entry['customer_name'] ?? ''} ${entry['customer_email'] ?? ''}\n$balance · $match',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final duplicates = _mapList(_review['possible_duplicates']);
    final canSubmit =
        !_busy &&
        _checked &&
        _selected != null &&
        (duplicates.isEmpty || _notDuplicate);
    void close() {
      if (!_saving) Navigator.of(context).pop();
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BankEmailFacts(facts: _facts),
                if (_review['action'] == 'possible_duplicate')
                  Text(
                    BankAccountStrings.emailOutcomePossibleDuplicate,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                BankEmailPossibleDuplicates(duplicates: duplicates),
                const SizedBox(height: 8),
                Text(BankAccountStrings.emailLookupPayableOnly),
                if (widget.lookup != null) ...[
                  TextField(
                    controller: _query,
                    enabled: !_busy,
                    decoration: InputDecoration(
                      labelText: BankAccountStrings.emailLookupHint,
                    ),
                    onSubmitted: (_) => _search(),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _search,
                    child: Text(BankAccountStrings.emailLookup),
                  ),
                ],
                if (_task == _ConfirmationTask.search)
                  const LinearProgressIndicator(),
                if (_candidates.isEmpty)
                  Text(BankAccountStrings.emailNoCandidates)
                else
                  RadioGroup<int>(
                    groupValue: _selected,
                    onChanged: (value) => setState(() => _selected = value),
                    child: Column(
                      children: _candidates.map(_candidate).toList(),
                    ),
                  ),
                CheckboxListTile(
                  key: const ValueKey('email-attestation-checkbox'),
                  value: _checked,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _checked = v == true),
                  title: Text(BankAccountStrings.emailAttestation),
                ),
                if (duplicates.isNotEmpty)
                  CheckboxListTile(
                    key: const ValueKey('email-not-duplicate-checkbox'),
                    value: _notDuplicate,
                    onChanged: _busy
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
            onPressed: canSubmit ? _submit : null,
            child: Text(BankAccountStrings.emailConfirm),
          ),
        ],
      ),
    );
  }
}

class _BankEmailDismissDialog extends StatefulWidget {
  const _BankEmailDismissDialog({required this.dismiss});
  final Future<void> Function(String reason) dismiss;

  @override
  State<_BankEmailDismissDialog> createState() => _DismissState();
}

class _DismissState extends State<_BankEmailDismissDialog> {
  String _reason = '';
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    final done = await ExceptionHandler.guard(
      context,
      futureFunction: () async {
        await widget.dismiss(_reason.trim());
        return true;
      },
    );
    if (!mounted) return;
    setState(() => _saving = false);
    if (done == true) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    void close() {
      if (!_saving) Navigator.of(context).pop();
    }

    return PopScope(
      canPop: !_saving,
      child: AppAlertDialog(
        title: Text(BankAccountStrings.emailDismiss),
        dismissible: !_saving,
        onClose: close,
        content: TextField(
          maxLength: 240,
          enabled: !_saving,
          onChanged: (value) => setState(() => _reason = value),
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
            onPressed: _saving || _reason.trim().isEmpty ? null : _save,
            child: Text(BankAccountStrings.emailDismiss),
          ),
        ],
      ),
    );
  }
}
