import 'package:fstapp/data_services/client_sync/client_command_identity.dart';

import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import '../../_shared/common_strings.dart';
import '../../_shared/copy_button.dart';
import '../../forms/payment_method_strings.dart';
import '../../../services/utilities_all.dart';
import '../db_orders.dart';
import '../models/payment_operation_context.dart';
import '../models/payment_refund_recipient.dart';
import '../orders_strings.dart';
import '../payment_operation_strings.dart';

typedef PaymentOperationSubmit = Future<Map<String, dynamic>> Function(
  Map<String, dynamic> input,
);

/// One compact form for both money directions. Server capabilities own methods;
/// local success and bank instructions are deliberately different next actions.
class PaymentOperationDialog extends StatefulWidget {
  const PaymentOperationDialog({
    super.key,
    required this.orderId,
    required this.currency,
    required this.context,
    this.refund = false,
    this.refundRecipients = const [],
    this.bankOptions,
    this.onSubmit,
    this.onPreview,
    this.onBankInstructions,
    this.initialPendingPayload,
  });
  final int orderId;
  final String currency;
  final PaymentOperationContext context;
  final bool refund;
  final List<PaymentRefundRecipient> refundRecipients;
  final Widget? bankOptions;
  final PaymentOperationSubmit? onSubmit, onPreview, onBankInstructions;
  final Map<String, dynamic>? initialPendingPayload;
  @override
  State<PaymentOperationDialog> createState() => _PaymentOperationDialogState();
}

class _PaymentOperationDialogState extends State<PaymentOperationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _clientIntentId = ClientCommandIdentity.newCommandId();
  final _amount = TextEditingController();
  final _note = TextEditingController();
  final _iban = TextEditingController();
  final _name = TextEditingController();
  late PaymentOperationContext _context = widget.context;
  DateTime _selectedDate = DateTime.now();
  String? _method;
  bool _saving = false, _changed = false, _confirmNotSent = false;
  String? _error;
  Map<String, dynamic>? _frozenPayload, _request, _preview, _instructions;
  Timer? _previewTimer;
  int _previewRevision = 0;
  bool _previewing = false, _previewFailed = false;
  String? _previewAmount, _previewMethod;
  bool get _hasCurrentPreview =>
      _preview != null &&
      !_previewing &&
      _previewAmount == _amount.text.replaceAll(',', '.') &&
      _previewMethod == _method;

  void _draftChanged() {
    _previewTimer?.cancel();
    final revision = ++_previewRevision;
    setState(() {
      _preview = null;
      _previewFailed = false;
      _previewing = false;
    });
    if (!widget.refund || _bank || _request != null || _selected == null) {
      return;
    }
    final amount = _amount.text.replaceAll(',', '.');
    if (!RegExp(r'^[0-9]{1,8}(\.[0-9]{1,2})?$').hasMatch(amount) ||
        (double.tryParse(amount) ?? 0) <= 0 ||
        double.parse(amount) > (double.tryParse(_context.available) ?? 0)) {
      return;
    }
    setState(() => _previewing = true);
    _previewTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        final preview =
            await (widget.onPreview ?? DbOrders.previewPaymentOperation)({
              'orderId': widget.orderId,
              'method': _method,
              'amount': amount,
              'currency': widget.currency,
            });
        if (!mounted || revision != _previewRevision) return;
        if (preview['currency'] != widget.currency ||
            preview['netAfter'] is! String ||
            preview['availableAfter'] is! String ||
            preview['paidThreshold'] is! String ||
            preview['eligibleAfter'] is! bool ||
            preview['lifecyclePreserved'] is! bool) {
          throw StateError('PAYMENT_PREVIEW_INVALID');
        }
        setState(() {
          _preview = preview;
          _previewAmount = amount;
          _previewMethod = _method;
          _previewing = false;
        });
      } catch (_) {
        if (mounted && revision == _previewRevision) {
          setState(() {
            _previewing = false;
            _previewFailed = true;
          });
        }
      }
    });
  }

  List<PaymentOperationMethod> get _methods => _context.methods
      .where((m) => widget.refund ? m.canStartRefund : m.record)
      .toList();
  PaymentOperationMethod? get _selected {
    for (final method in _methods) {
      if (method.id == _method) return method;
    }
    return null;
  }

  bool get _bank => _selected?.verification == 'bank_event';
  @override
  void initState() {
    super.initState();
    _method = _methods.firstOrNull?.id;
    if (widget.refund) {
      if ((double.tryParse(_context.available) ?? 0) > 0) {
        _amount.text = _context.available;
      }
      if (widget.refundRecipients.length == 1) {
        _iban.text = widget.refundRecipients.single.iban;
        _name.text = widget.refundRecipients.single.name;
      }
    }
    final pending = widget.initialPendingPayload;
    if (pending != null) {
      if (pending['orderId'] != widget.orderId) {
        throw StateError('PAYMENT_RECOVERY_SCOPE_MISMATCH');
      }
      _frozenPayload = Map<String, dynamic>.unmodifiable(pending);
      _method = pending['method']?.toString();
      _amount.text = pending['amount']?.toString() ?? '';
      _note.text = pending['note']?.toString() ?? '';
      _iban.text = pending['recipientIban']?.toString() ?? '';
      _name.text = pending['recipientName']?.toString() ?? '';
      _selectedDate =
          DateTime.tryParse('${pending['receivedAt']}')?.toLocal() ??
          _selectedDate;
      _error = PaymentOperationStrings.text('uncertain');
    }
    if (widget.refund) {
      for (final r in _context.requests) {
        if (pending != null &&
            (pending['operation'] != 'cancel_pending' ||
                pending['requestId'] != r['id'])) {
          continue;
        }
        if (const {
              'pending',
              'action_required',
              'unknown',
              'processing',
            }.contains(r['status']) &&
            r['canReopen'] == true) {
          _request = r;
          break;
        }
      }
    }
    if (widget.refund && pending == null && _request == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _draftChanged();
      });
    }
  }

  @override
  void didUpdateWidget(covariant PaymentOperationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.context != oldWidget.context) {
      _context = widget.context;
      if (_request != null) {
        Map<String, dynamic>? current;
        for (final request in _context.requests) {
          if (request['id'] == _request!['id'] &&
              request['canReopen'] == true) {
            current = request;
          }
        }
        _request = current;
        if (_request?['canCancel'] != true) _confirmNotSent = false;
      }
      if (!_methods.any((method) => method.id == _method)) {
        _method = _methods.firstOrNull?.id;
      }
      _draftChanged();
    }
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    _previewRevision++;
    _amount.dispose();
    _note.dispose();
    _iban.dispose();
    _name.dispose();
    super.dispose();
  }

  String _money(Object? value) => Utilities.formatPrice(
    context,
    double.tryParse('$value') ?? 0,
    currencyCode: widget.currency,
    decimalDigits: 2,
  );
  void _close() {
    if (!_saving) Navigator.of(context).pop(_changed);
  }

  Future<void> _submit({bool cancel = false}) async {
    if (_saving) return;
    if (!cancel && widget.refund && _bank && _frozenPayload == null) {
      await _generateBankInstructions();
      return;
    }
    if (_frozenPayload == null) {
      if (cancel) {
        if (!_confirmNotSent || _request?['canCancel'] != true) return;
        _frozenPayload = {
          'operation': 'cancel_pending',
          'clientIntentId': _clientIntentId,
          'orderId': widget.orderId,
          'requestId': _request!['id'],
          'transferNotSubmitted': true,
        };
      } else {
        if (_selected == null ||
            !_formKey.currentState!.validate() ||
            (widget.refund && !_hasCurrentPreview)) {
          return;
        }
        _frozenPayload = {
          'operation': widget.refund ? 'prepare_refund' : 'record_payment',
          'clientIntentId': _clientIntentId,
          'orderId': widget.orderId,
          'method': _method,
          'amount': _amount.text.replaceAll(',', '.'),
          'currency': widget.currency,
          'receivedAt': _selectedDate.toUtc().toIso8601String(),
          'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
          if (_bank) ...{
            'recipientIban': _iban.text.replaceAll(' ', '').toUpperCase(),
            'recipientName': _name.text.trim(),
          },
        };
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result =
          await (widget.onSubmit ?? DbOrders.commandPaymentOperation)(
            _frozenPayload!,
          );
      if (!mounted) return;
      _changed = true;
      final response = result['data'] is Map
          ? Map<String, dynamic>.from(result['data'])
          : result;
      if (response['nextAction'] == 'recorded' || cancel) {
        Navigator.of(context).pop(true);
        return;
      }
      final request = response['request'];
      if (request is! Map) {
        throw StateError('PAYMENT_RECEIPT_INVALID');
      }
      setState(() {
        _request = Map<String, dynamic>.from(request);
        if (response['context'] is Map) {
          _context = PaymentOperationContext.fromJson(response['context']);
        }
        _frozenPayload = null;
      });
    } on PaymentOperationRejected {
      if (mounted) {
        setState(() {
          _frozenPayload = null;
          _error = PaymentOperationStrings.text('notApplied');
          // Deterministic rollback permits editing; stale financial preview does not.
          _preview = null;
        });
      }
      if (widget.refund && mounted) _draftChanged();
    } catch (_) {
      if (mounted) {
        setState(() => _error = PaymentOperationStrings.text('uncertain'));
      }
      // Keep the original amount/date/command payload through uncertain results.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateBankInstructions() async {
    if (_selected?.instructions != true || !_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final instructions =
          await (widget.onBankInstructions ?? DbOrders.bankRefundInstructions)({
            'orderId': widget.orderId,
            'amount': _amount.text.replaceAll(',', '.'),
            'currency': widget.currency,
            'recipientIban': _iban.text.replaceAll(' ', '').toUpperCase(),
            'recipientName': _name.text.trim(),
          });
      if (!isBankRefundInstruction(instructions, widget.orderId)) {
        throw StateError('PAYMENT_REFUND_UNAVAILABLE');
      }
      if (mounted) setState(() => _instructions = instructions);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = PaymentOperationStrings.bankQrError(
            error is PaymentInstructionsException ? error.code : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _bankInstructions() {
    final instructions = _instructions!;
    final payload = instructions['payload'];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(PaymentOperationStrings.text('bankQrReady')),
        if (payload is String && payload.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ColoredBox(
                color: Colors.white,
                child: QrImageView(data: payload, size: 220),
              ),
            ),
          ),
        for (final key in ['recipientName', 'recipientIban', 'reference'])
          if (instructions[key] != null)
            _fact(PaymentOperationStrings.text(key), instructions[key]),
        _fact(
          CommonStrings.amount,
          '${instructions['amount']} ${widget.currency}',
        ),
      ],
    );
  }

  Future<void> _correct(Map<String, dynamic> request) async {
    final reason = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AppAlertDialog(
          onClose: () => Navigator.of(dialogContext).pop(false),
          title: Text(PaymentOperationStrings.text('correctRefund')),
          content: TextField(
            controller: reason,
            autofocus: true,
            onChanged: (_) => update(() {}),
            decoration: InputDecoration(
              labelText: PaymentOperationStrings.text('correctionReason'),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(CommonStrings.cancel),
            ),
            ElevatedButton(
              onPressed: reason.text.trim().isEmpty
                  ? null
                  : () => Navigator.of(dialogContext).pop(true),
              child: Text(PaymentOperationStrings.text('correctRefund')),
            ),
          ],
        ),
      ),
    );
    final explanation = reason.text.trim();
    reason.dispose();
    if (accepted != true || !mounted) return;
    _frozenPayload = {
      'operation': 'correct_record',
      'clientIntentId': _clientIntentId,
      'orderId': widget.orderId,
      'method': 'cash',
      'requestId': request['id'],
      'reason': explanation,
    };
    await _submit();
  }

  Widget _fact(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Flexible(child: SelectableText('$value')),
        CopyButton(value: '$value'),
      ],
    ),
  );

  Widget _pending() {
    final bank =
        _request!['method'] == 'bank' &&
        _request!['verification'] == 'bank_event';
    final allowed = isBankRefundInstruction(
      _request!,
      widget.orderId,
      request: true,
    );
    final instructions = allowed && _request!['instructions'] is Map
        ? _request!['instructions'] as Map
        : const {};
    final payload = allowed ? instructions['payload'] : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(PaymentOperationStrings.text(bank ? 'bankPending' : 'processing')),
        const SizedBox(height: 8),
        Text(
          PaymentOperationStrings.text(
            bank
                ? (payload is String && payload.isNotEmpty
                      ? 'bankPrepared'
                      : 'bankManualPrepared')
                : 'providerPending',
          ),
        ),
        if (payload is String && payload.isNotEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: ColoredBox(
                color: Colors.white,
                child: QrImageView(data: payload, size: 220),
              ),
            ),
          ),
        if (bank) ...[
          for (final key in [
            'sourceAccount',
            'recipientName',
            'recipientIban',
            'reference',
          ])
            if (instructions[key] != null)
              _fact(PaymentOperationStrings.text(key), instructions[key]),
          _fact(
            CommonStrings.amount,
            '${instructions['amount'] ?? _request!['amount']} ${widget.currency}',
          ),
          if (instructions['lastSyncedAt'] != null)
            _fact(
              PaymentOperationStrings.text('lastSyncedAt'),
              DateFormat.yMd(Localizations.localeOf(context).toString())
                  .add_jm()
                  .format(
                    DateTime.parse('${instructions['lastSyncedAt']}').toLocal(),
                  ),
            ),
          const SizedBox(height: 12),
          Text(PaymentOperationStrings.text('sourceWarning')),
        ],
        if (_request!['canCancel'] == true)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _confirmNotSent,
            onChanged: _saving || _frozenPayload != null
                ? null
                : (v) => setState(() => _confirmNotSent = v == true),
            title: Text(PaymentOperationStrings.text('confirmNotSent')),
          ),
        if (_request!['canCancel'] == true && _confirmNotSent)
          Text(PaymentOperationStrings.text('cancelWarning')),
      ],
    );
  }

  bool get _supportsBankQr => const {'CZK', 'EUR'}.contains(widget.currency);

  Widget _refundMethods(bool locked) {
    final methods = _context.methods
        .where((method) => method.canStartRefund)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            PaymentOperationStrings.text('refundMethod'),
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          for (final method in methods)
            ListTile(
              key: ValueKey('refundMethod_${method.id}'),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              selected: method.id == _method,
              selectedTileColor: Theme.of(context)
                  .colorScheme
                  .secondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              enabled: !locked && method.canStartRefund,
              leading: Icon(
                method.verification == 'bank_event'
                    ? (_supportsBankQr
                          ? Icons.qr_code_2
                          : Icons.account_balance_outlined)
                    : method.id == 'cash'
                    ? Icons.payments_outlined
                    : Icons.credit_card,
              ),
              title: Text(
                method.verification == 'bank_event'
                    ? PaymentOperationStrings.text(
                        _supportsBankQr ? 'prepareBank' : 'prepareTransfer',
                      )
                    : method.id == 'cash'
                    ? PaymentOperationStrings.text('cash')
                    : method.displayName,
              ),
              subtitle: method.verification == 'bank_event'
                  ? Text(
                      PaymentOperationStrings.text(
                        method.instructions ? 'bankHint' : 'bankUnavailable',
                      ),
                    )
                  : method.id == 'cash'
                  ? Text(PaymentOperationStrings.text('cashHint'))
                  : null,
              trailing: Icon(
                method.id == _method
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
              ),
              onTap: locked || !method.canStartRefund
                  ? null
                  : () {
                      setState(() => _method = method.id);
                      _draftChanged();
                    },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locked = _saving || _frozenPayload != null;
    return PopScope(
      canPop: !_saving,
      child: AppAlertDialog(
        onClose: _close,
        dismissible: !_saving,
        title: Text(
          widget.refund
              ? PaymentOperationStrings.text('refund')
              : OrdersStrings.addCashPaymentTitle,
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_instructions != null)
                  _bankInstructions()
                else if (_request != null)
                  _pending()
                else
                  Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.refund) ...[
                          Text(
                            '${PaymentOperationStrings.text('available')}: ${_money(_context.available)}',
                          ),
                          if (double.tryParse(_context.pending) != 0)
                            Text(
                              '${PaymentOperationStrings.text('pending')}: ${_money(_context.pending)}',
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (widget.refund && _context.invalidIdentity)
                          Text(
                            PaymentOperationStrings.text('ledgerIncomplete'),
                          ),
                        if (widget.refund) _refundMethods(locked),
                        if (!widget.refund && _methods.length > 1)
                          DropdownButtonFormField<String>(
                            initialValue: _method,
                            isExpanded: true,
                            items: _methods
                                .map(
                                  (m) => DropdownMenuItem(
                                    value: m.id,
                                    child: Text(
                                      m.id == 'cash'
                                          ? PaymentOperationStrings.text('cash')
                                          : m.id == 'bank'
                                          ? PaymentMethodStrings.text('bank')
                                          : m.displayName,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: locked
                                ? null
                                : (v) {
                                    setState(() => _method = v);
                                    _draftChanged();
                                  },
                          ),
                        if (_methods.isEmpty)
                          Text(PaymentOperationStrings.text('unavailable')),
                        TextFormField(
                          key: const ValueKey('paymentAmount'),
                          onChanged: (_) => _draftChanged(),
                          controller: _amount,
                          readOnly:
                              widget.refund &&
                              _selected?.partialRefundSupported != true,
                          autofocus: true,
                          enabled: !locked,
                          decoration: InputDecoration(
                            labelText: CommonStrings.amount,
                            suffixText: widget.currency,
                            hintText: '0',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            TextInputFormatter.withFunction(
                              (oldValue, newValue) =>
                                  newValue.text.contains('-')
                                  ? oldValue
                                  : newValue,
                            ),
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9,.]'),
                            ),
                          ],
                          validator: (v) {
                            if (v == null ||
                                !RegExp(r'^[0-9]{1,8}([,.][0-9]{1,2})?$')
                                    .hasMatch(v) ||
                                (double.tryParse(v.replaceAll(',', '.')) ??
                                        0) <=
                                    0) {
                              return PaymentMethodStrings.text(
                                'cashAmountInvalid',
                              );
                            }
                            if (widget.refund &&
                                double.parse(v.replaceAll(',', '.')) >
                                    (double.tryParse(_context.available) ??
                                        0)) {
                              return PaymentOperationStrings.text(
                                'exceedsAvailable',
                              );
                            }
                            return null;
                          },
                        ),
                        if (_previewing)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              PaymentOperationStrings.text('previewing'),
                            ),
                          ),
                        if (_previewFailed)
                          TextButton(
                            onPressed: locked ? null : _draftChanged,
                            child: Text(
                              PaymentOperationStrings.text(
                                'previewUnavailable',
                              ),
                            ),
                          ),
                        if (_preview != null) ...[
                          _fact(
                            PaymentOperationStrings.text('netAfter'),
                            _money(_preview!['netAfter']),
                          ),
                          _fact(
                            PaymentOperationStrings.text('availableAfter'),
                            _money(_preview!['availableAfter']),
                          ),
                          _fact(
                            PaymentOperationStrings.text('paidThreshold'),
                            _money(_preview!['paidThreshold']),
                          ),
                          if (_preview!['lifecyclePreserved'] == true)
                            Text(
                              PaymentOperationStrings.text(
                                'lifecyclePreserved',
                              ),
                            )
                          else if (_preview!['eligibleAfter'] == false)
                            Text(
                              PaymentOperationStrings.text('belowThreshold'),
                            ),
                        ],
                        if (_bank) ...[
                          const SizedBox(height: 12),
                          Text(
                            PaymentOperationStrings.text('recipientAccount'),
                          ),
                          if (widget.refundRecipients.length > 1)
                            DropdownButtonFormField<String>(
                              key: const ValueKey('refundRecipientAccount'),
                              isExpanded: true,
                              decoration: InputDecoration(
                                labelText: PaymentOperationStrings.text(
                                  'chooseIncomingAccount',
                                ),
                              ),
                              items: widget.refundRecipients
                                  .map(
                                    (recipient) => DropdownMenuItem(
                                      value: recipient.iban,
                                      child: Text(
                                        '${recipient.name} ${recipient.iban}'
                                            .trim(),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: locked
                                  ? null
                                  : (iban) {
                                      final recipient = widget.refundRecipients
                                          .firstWhere((r) => r.iban == iban);
                                      setState(() {
                                        _iban.text = recipient.iban;
                                        _name.text = recipient.name;
                                      });
                                    },
                            ),
                          TextFormField(
                            controller: _name,
                            enabled: !locked,
                            decoration: InputDecoration(
                              labelText: PaymentOperationStrings.text(
                                'recipientName',
                              ),
                            ),
                            validator: (v) => v == null || v.trim().isEmpty
                                ? CommonStrings.fieldCannotBeEmpty
                                : null,
                          ),
                          TextFormField(
                            controller: _iban,
                            onChanged: (_) => setState(() {}),
                            enabled: !locked,
                            decoration: InputDecoration(
                              labelText: PaymentOperationStrings.text(
                                'recipientIban',
                              ),
                              errorMaxLines: 4,
                              helperText:
                                  widget.refundRecipients.any(
                                    (r) =>
                                        r.iban ==
                                        _iban.text
                                            .replaceAll(RegExp(r'\s'), '')
                                            .toUpperCase(),
                                  )
                                  ? PaymentOperationStrings.text(
                                      'incomingAccountHint',
                                    )
                                  : PaymentOperationStrings.text(
                                      'manualAccountHint',
                                    ),
                              helperMaxLines: 3,
                            ),
                            validator: (v) {
                              final iban = (v ?? '')
                                  .replaceAll(' ', '')
                                  .toUpperCase();
                              if (!RegExp(r'^[A-Z]{2}[0-9]{2}[A-Z0-9]{11,30}$')
                                  .hasMatch(iban)) {
                                return PaymentOperationStrings.text(
                                  'invalidIban',
                                );
                              }
                              if (widget.currency == 'CZK' &&
                                  !iban.startsWith('CZ')) {
                                return PaymentOperationStrings.text(
                                  'qrDomesticAccountRequired',
                                );
                              }
                              return null;
                            },
                          ),
                        ],
                        const SizedBox(height: 16),
                        if (!_bank)
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: Text(
                              CommonStrings.advancedSettings,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            children: [
                              InkWell(
                                onTap: locked
                                    ? null
                                    : () async {
                                        final date = await showDatePicker(
                                          context: context,
                                          initialDate: _selectedDate,
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2100),
                                        );
                                        if (date != null && mounted) {
                                          setState(() => _selectedDate = date);
                                        }
                                      },
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: CommonStrings.date,
                                  ),
                                  child: Text(
                                    DateFormat.yMd(
                                      Localizations.localeOf(context)
                                          .toString(),
                                    ).format(_selectedDate),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _note,
                                enabled: !locked,
                                decoration: InputDecoration(
                                  labelText: CommonStrings.note,
                                ),
                              ),
                            ],
                          ),
                        if (widget.refund)
                          for (final request in _context.requests.where(
                            (r) => r['canCorrect'] == true,
                          ))
                            TextButton(
                              onPressed: locked
                                  ? null
                                  : () => _correct(request),
                              child: Text(
                                '${PaymentOperationStrings.text('correctRefund')}: ${_money(request['amount'])}',
                              ),
                            ),
                        if (!widget.refund && widget.bankOptions != null) ...[
                          const SizedBox(height: 16),
                          widget.bankOptions!,
                        ],
                      ],
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : _close,
            child: Text(
              _request == null && _instructions == null
                  ? CommonStrings.cancel
                  : PaymentOperationStrings.text('close'),
            ),
          ),
          if ((_request == null && _instructions == null) ||
              _frozenPayload != null)
            ElevatedButton(
              onPressed:
                  _saving ||
                      (_request == null &&
                          _methods.isEmpty &&
                          _frozenPayload == null) ||
                      (_frozenPayload?['operation'] == 'cancel_pending' &&
                          _request?['canCancel'] != true) ||
                      (widget.refund &&
                          !_bank &&
                          _request == null &&
                          _frozenPayload == null &&
                          !_hasCurrentPreview)
                  ? null
                  : () => _submit(),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      _frozenPayload != null
                          ? PaymentOperationStrings.text('verifySameCommand')
                          : !widget.refund
                          ? OrdersStrings.addPayment
                          : _bank
                          ? PaymentOperationStrings.text(
                              _supportsBankQr
                                  ? 'prepareBank'
                                  : 'prepareTransfer',
                            )
                          : _selected?.verification == 'local_commit'
                          ? PaymentOperationStrings.text('recordCashRefund')
                          : '${PaymentOperationStrings.text('refundVia')} ${_selected?.displayName ?? ''}',
                    ),
            ),
          if (_instructions != null)
            TextButton(
              onPressed: () => setState(() => _instructions = null),
              child: Text(CommonStrings.edit),
            ),
          if (_request?['canCancel'] == true &&
              _confirmNotSent &&
              _frozenPayload == null)
            TextButton(
              onPressed: _saving ? null : () => _submit(cancel: true),
              child: Text(PaymentOperationStrings.text('cancelPending')),
            ),
        ],
      ),
    );
  }
}
