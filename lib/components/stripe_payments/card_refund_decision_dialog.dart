import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'card_refund_decision_api.dart';
import 'card_refund_decision_strings.dart';

class CardRefundDecisionDialog extends StatefulWidget {
  const CardRefundDecisionDialog(
      {super.key, required this.detail, required this.api});
  final CardRefundDetail detail;
  final CardRefundDecisionApi api;
  @override
  State<CardRefundDecisionDialog> createState() =>
      _CardRefundDecisionDialogState();
}

class _CardRefundDecisionDialogState extends State<CardRefundDecisionDialog> {
  final _form = GlobalKey<FormState>();
  final _note = TextEditingController();
  final _errorFocus = FocusNode();
  final _selected = <int>{};
  String? _action, _error;
  bool _busy = false, _mustRefresh = false;
  late CardRefundDetail _detail = widget.detail;
  String t(String key) => CardRefundDecisionStrings.text(key);
  @override
  void dispose() {
    _note.dispose();
    _errorFocus.dispose();
    super.dispose();
  }

  void _showError(String message) {
    setState(() => _error = message);
    _errorFocus.requestFocus();
  }

  Future<void> _submit() async {
    final valid = _form.currentState!.validate();
    if (_action == null ||
        (_action == 'cancel_selected' && _selected.isEmpty)) {
      _showError(t('chooseAction'));
      return;
    }
    if (!valid) {
      _showError(t('noteValidation'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.decide(
          detail: _detail,
          action: _action!,
          ticketIds: _action == 'keep' ? [] : _selected.toList(),
          note: _note.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _mustRefresh =
            error.toString().contains('STRIPE_REFUND_REVISION_CHANGED') ||
                error.toString().contains('STRIPE_REFUND_TICKET_UNAVAILABLE') ||
                error.toString().contains('STRIPE_PARTIAL_REFUND_REQUIRED');
      });
      _showError(CardRefundDecisionStrings.error(error));
    }
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    try {
      final detail = await widget.api.read(_detail.orderId);
      if (!mounted) return;
      if (detail == null || !detail.canDecide) {
        setState(() => _busy = false);
        _showError(t('notPartial'));
        return;
      }
      setState(() {
        _detail = detail;
        _action = null;
        _selected.clear();
        _mustRefresh = false;
        _error = null;
        _busy = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        _showError(t('failed'));
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AppAlertDialog(
          dismissible: !_busy,
          onClose: () {
            if (!_busy) Navigator.of(context).pop(false);
          },
          title: Text(t('title')),
          content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                  child: Form(
                key: _form,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                          '${t('refunded')}: ${CardRefundDecisionStrings.amount(_detail.refundedMinor, _detail.currency, locale: Localizations.localeOf(context).toLanguageTag())}',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(t('explanation')),
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Focus(
                            focusNode: _errorFocus,
                            child: Semantics(
                                liveRegion: true,
                                child: Text(_error!,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error)))),
                        if (_mustRefresh)
                          Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                  onPressed: _busy ? null : _refresh,
                                  child: Text(t('refresh')))),
                      ],
                      const SizedBox(height: 16),
                      RadioGroup<String>(
                          groupValue: _action,
                          onChanged: (value) {
                            if (!_busy) setState(() => _action = value);
                          },
                          child: Column(children: [
                            RadioListTile<String>(
                                value: 'keep',
                                enabled: !_busy,
                                title: Text(t('keep')),
                                subtitle: Text(t('keepHint')),
                                contentPadding: EdgeInsets.zero),
                            RadioListTile<String>(
                                value: 'cancel_selected',
                                enabled: !_busy,
                                title: Text(t('cancelSelected')),
                                subtitle: Text(t('cancelHint')),
                                contentPadding: EdgeInsets.zero),
                          ])),
                      if (_action == 'cancel_selected') ...[
                        for (final ticket in _detail.tickets)
                          CheckboxListTile(
                              key: ValueKey('refund-ticket-${ticket.id}'),
                              value: _selected.contains(ticket.id),
                              onChanged: !_busy && ticket.canCancel
                                  ? (value) => setState(() {
                                        if (value == true) {
                                          _selected.add(ticket.id);
                                        } else {
                                          _selected.remove(ticket.id);
                                        }
                                      })
                                  : null,
                              title: Text(ticket.label),
                              subtitle: ticket.canCancel
                                  ? null
                                  : Text(t(ticket.state == 'used'
                                      ? 'used'
                                      : 'ineligible')),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                          controller: _note,
                          enabled: !_busy,
                          maxLength: 500,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                              labelText: t('note'),
                              border: const OutlineInputBorder()),
                          validator: (value) =>
                              (value?.trim().length ?? 0) < 3 ||
                                      (value?.trim().length ?? 0) > 500
                                  ? t('noteValidation')
                                  : null),
                    ]),
              ))),
          actions: [
            TextButton(
                onPressed:
                    _busy ? null : () => Navigator.of(context).pop(false),
                child: Text(CommonStrings.storno)),
            FilledButton(
                onPressed: _busy || _mustRefresh || !_detail.canDecide
                    ? null
                    : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(t('save'))),
          ],
        ),
      );
}
