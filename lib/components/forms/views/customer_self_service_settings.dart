import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'package:festapp_core/eshop.dart';

import '../models/form_editor_draft.dart';
import '../models/form_bundle.dart';
import '../db_forms.dart';
import '../customer_order_changes.dart';
import '../../features/feature_service.dart';
import '../../features/feature_constants.dart';

/// An owned editor draft. Only the surrounding form Save persists these rules.
class CustomerSelfServiceSettings extends StatefulWidget {
  const CustomerSelfServiceSettings({
    super.key,
    required this.form,
    required this.canEdit,
    required this.onChanged,
  });
  final FormEditorDraft form;
  final bool canEdit;
  final VoidCallback onChanged;
  @override
  State<CustomerSelfServiceSettings> createState() =>
      _CustomerSelfServiceSettingsState();
}

class _CustomerSelfServiceSettingsState
    extends State<CustomerSelfServiceSettings> {
  late final Map<String, dynamic> _policy = Map<String, dynamic>.from(
    jsonDecode(
      jsonEncode(widget.form.definition.customerSelfService?['policy'] ?? {}),
    ) as Map,
  );
  List<FormBundle>? _catalog;
  final Map<int, FormEditorDraft> _targets = {};
  String? _error;
  bool get _enabled =>
      FeatureService.isFeatureEnabled(FeatureConstants.customerSelfService);
  Map<String, dynamic> _rule(String op) => _policy.putIfAbsent(
    op,
    () => op == 'edit'
        ? {'enabled': false, 'fields': <dynamic>[]}
        : op == 'cancel'
        ? {
            'enabled': false,
            'mode': 'approval_required',
            'reason_required': false,
            'refund_mode': 'none',
          }
        : {'enabled': false, 'targets': <dynamic>[]},
  );
  void _change() {
    widget.form.customerPolicyDirty = true;
    widget.form.definition = widget.form.definition.copyWith(
      customerSelfService: {
        ...?widget.form.definition.customerSelfService,
        'policy': jsonDecode(jsonEncode(_policy)),
      },
    );
    widget.onChanged();
    setState(() {});
  }

  List<ProductModel> _products(FormEditorDraft form) => {
    for (final f in form.relatedFields)
      for (final p in f.definition.productType?.products ?? <ProductModel>[])
        p.id: p,
  }.values.toList();
  Future<void> _loadCatalog() async {
    try {
      final forms = await DbForms.getAllFormsForOccasionOrUnit();
      if (mounted) {
        setState(
          () => _catalog = forms
              .where((f) => f.definition.id != widget.form.definition.id)
              .toList(),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    }
  }

  Future<void> _loadTarget(FormBundle form) async {
    try {
      final bundle = await DbForms.getFormForEdit(form.definition.link!);
      if (mounted && bundle != null) {
        setState(() => _targets[form.definition.id!] = bundle.form);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'failed');
    }
  }

  Widget _date(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> changed, {
    bool required = false,
  }) {
    final wall = value == null ? null : TimeHelper.eventTime.atInstant(value);
    void save(DateTime day, TimeOfDay time) {
      final instants = TimeHelper.eventTime.instantsForWallTime(
        DateTime(day.year, day.month, day.day, time.hour, time.minute),
      );
      if (instants.length != 1) {
        setState(() => _error = 'invalidTime');
        return;
      }
      changed(instants.single);
      setState(() => _error = null);
    }

    return FormField<DateTime>(
      key: ValueKey('$label:${value?.toIso8601String()}'),
      initialValue: value,
      validator: (v) => required && v == null
          ? customerChangeText('deadlineRequired')
          : (label == customerChangeText('termEnd') &&
                v != null &&
                (widget.form.definition.termStartAt == null ||
                    !v.isAfter(widget.form.definition.termStartAt!)))
          ? customerChangeText('invalidTime')
          : null,
      builder: (state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            TimeDatePicker(
              date: wall,
              time: wall == null ? null : TimeOfDay.fromDateTime(wall),
              enabled: widget.canEdit,
              isValid: !state.hasError,
              onDateChanged: (day) => save(
                day,
                wall == null
                    ? const TimeOfDay(hour: 12, minute: 0)
                    : TimeOfDay.fromDateTime(wall),
              ),
              onTimeChanged: (time) => save(wall ?? TimeHelper.now(), time),
            ),
            if (state.errorText != null)
              Text(
                state.errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (value != null)
              TextButton(
                onPressed: widget.canEdit ? () => changed(null) : null,
                child: Text(customerChangeText('clearDate')),
              ),
          ],
        ),
      ),
    );
  }

  Widget _operation(String op) {
    final rule = _rule(op);
    final enabled = rule['enabled'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(customerChangeText(op)),
            value: enabled,
            onChanged: widget.canEdit && _enabled
                ? (v) {
                    rule['enabled'] = v;
                    _change();
                  }
                : null,
          ),
          if (enabled) ...[
            _date(
              customerChangeText('deadline'),
              DateTime.tryParse(rule['allowed_until']?.toString() ?? ''),
              (v) {
                if (v == null) {
                  rule.remove('allowed_until');
                } else {
                  rule['allowed_until'] = v.toUtc().toIso8601String();
                }
                _change();
              },
              required: true,
            ),
            if (op == 'cancel') ...[
              DropdownButtonFormField<String>(
                initialValue: rule['mode'] as String?,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: customerChangeText('cancellationMode'),
                ),
                items: [
                  for (final pair in {
                    'approval_required': 'approvalRequired',
                    'automatic': 'automatic',
                  }.entries)
                    DropdownMenuItem(
                      value: pair.key,
                      child: Text(customerChangeText(pair.value)),
                    ),
                ],
                onChanged: widget.canEdit
                    ? (v) {
                        rule['mode'] = v;
                        _change();
                      }
                    : null,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(customerChangeText('requireReason')),
                value: rule['reason_required'] == true,
                onChanged: widget.canEdit
                    ? (v) {
                        rule['reason_required'] = v;
                        _change();
                      }
                    : null,
              ),
              DropdownButtonFormField<String>(
                initialValue: rule['refund_mode'] as String?,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: customerChangeText('refundMode'),
                ),
                items: [
                  for (final pair in {
                    'none': 'none',
                    'manual': 'manualRefund',
                    'automatic': 'automaticRefund',
                  }.entries)
                    DropdownMenuItem(
                      value: pair.key,
                      enabled:
                          pair.key != 'automatic' ||
                          widget
                                  .form
                                  .definition
                                  .customerSelfService?['canEnableAutomaticRefund'] ==
                              true,
                      child: Text(customerChangeText(pair.value)),
                    ),
                ],
                onChanged: widget.canEdit
                    ? (v) {
                        rule['refund_mode'] = v;
                        _change();
                      }
                    : null,
              ),
            ],
            if (op == 'edit') ...[
              Text(customerChangeText('allowedFields')),
              for (final draft in widget.form.relatedFields)
                if (draft.definition.id != null &&
                    const [
                      'name',
                      'surname',
                      'phone',
                      'text',
                      'city',
                      'address',
                      'select_one',
                    ].contains(draft.definition.type) &&
                    draft.definition.isHidden != true)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      draft.definition.title ?? draft.definition.type ?? '',
                    ),
                    subtitle: draft.definition.isTicketField == true
                        ? Text(customerChangeText('participantField'))
                        : null,
                    value: (rule['fields'] as List).any(
                      (f) =>
                          f['id'] == draft.definition.id &&
                          f['type'] == draft.definition.type,
                    ),
                    onChanged: widget.canEdit
                        ? (v) {
                            (rule['fields'] as List).removeWhere(
                              (f) => f['id'] == draft.definition.id,
                            );
                            if (v == true) {
                              (rule['fields'] as List).add({
                                'id': draft.definition.id,
                                'type': draft.definition.type,
                              });
                            }
                            _change();
                          }
                        : null,
                  ),
            ],
            if (op == 'move') _targetRules(rule),
          ],
        ],
      ),
    );
  }

  Widget _targetRules(Map<String, dynamic> rule) {
    final configured = rule['targets'] as List;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(customerChangeText('targets')),
        Text(customerChangeText('mappingHelp')),
        if (_catalog == null)
          TextButton(
            onPressed: widget.canEdit ? _loadCatalog : null,
            child: Text(customerChangeText('loadTargets')),
          )
        else
          DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: customerChangeText('addTarget'),
            ),
            items: [
              for (final form in _catalog!)
                if (!configured.any((t) => t['formId'] == form.definition.id))
                  DropdownMenuItem(
                    value: form.definition.id,
                    child: Text(
                      form.definition.title ?? form.definition.link ?? '',
                    ),
                  ),
            ],
            onChanged: widget.canEdit
                ? (id) {
                    if (id == null) return;
                    configured.add({
                      'formId': id,
                      'products': <String, dynamic>{},
                      'fields': <String, dynamic>{},
                    });
                    _loadTarget(
                      _catalog!.firstWhere((f) => f.definition.id == id),
                    );
                    _change();
                  }
                : null,
          ),
        for (final target in configured) ...[
          const Divider(),
          Row(
            children: [
              Expanded(
                child: Text(
                  _targets[target['formId']]?.definition.title ??
                      _catalog
                          ?.where((f) => f.definition.id == target['formId'])
                          .firstOrNull
                          ?.definition
                          .title ??
                      customerChangeText('target'),
                ),
              ),
              IconButton(
                tooltip: customerChangeText('removeTarget'),
                onPressed: widget.canEdit
                    ? () {
                        configured.remove(target);
                        _change();
                      }
                    : null,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (!_targets.containsKey(target['formId']))
            TextButton(
              onPressed: widget.canEdit
                  ? () async {
                      if (_catalog == null) await _loadCatalog();
                      final form = _catalog
                          ?.where((f) => f.definition.id == target['formId'])
                          .firstOrNull;
                      if (form != null) await _loadTarget(form);
                    }
                  : null,
              child: Text(customerChangeText('loadMapping')),
            )
          else ...[
            for (final source in _products(widget.form))
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'product:${target['formId']}:${source.id}:${target['products'][source.id.toString()]}',
                ),
                initialValue: target['products'][source.id.toString()] as int?,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText:
                      '${customerChangeText('sourceProduct')}: ${source.title}',
                ),
                items: [
                  for (final product in _products(_targets[target['formId']]!))
                    DropdownMenuItem(
                      value: product.id,
                      child: Text(
                        '${product.title} (${product.price} ${product.currencyCode})',
                      ),
                    ),
                ],
                onChanged: widget.canEdit
                    ? (v) {
                        target['products'][source.id.toString()] = v;
                        _change();
                      }
                    : null,
              ),
            for (final source in widget.form.relatedFields)
              if (source.definition.id != null &&
                  const [
                    'name',
                    'surname',
                    'phone',
                    'email',
                    'text',
                    'city',
                    'address',
                    'select_one',
                  ].contains(source.definition.type))
                DropdownButtonFormField<int>(
                  key: ValueKey(
                    'field:${target['formId']}:${source.definition.id}:${target['fields'][source.definition.id.toString()]}',
                  ),
                  initialValue:
                      target['fields'][source.definition.id.toString()] as int?,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText:
                        '${customerChangeText('sourceField')}: ${source.definition.title}',
                  ),
                  items: [
                    for (final field
                        in _targets[target['formId']]!.relatedFields)
                      if (field.definition.type == source.definition.type &&
                          field.definition.isTicketField ==
                              source.definition.isTicketField &&
                          field.definition.isHidden != true)
                        DropdownMenuItem(
                          value: field.definition.id,
                          child: Text(field.definition.title ?? ''),
                        ),
                  ],
                  onChanged: widget.canEdit
                      ? (v) {
                          target['fields'][source.definition.id.toString()] = v;
                          _change();
                        }
                      : null,
                ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(customerChangeText('saveRules')),
    children: [
      customerChangesHelp(context),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Text(customerChangeText('answersLocked')),
      ),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!_enabled) Text(customerChangeText('offHelp')),
            Text(customerChangeText('termHelp')),
            _date(
              customerChangeText('termStart'),
              widget.form.definition.termStartAt,
              (v) {
                widget.form.definition = widget.form.definition.copyWith(
                  termStartAt: v,
                  termEndAt: v == null
                      ? null
                      : widget.form.definition.termEndAt,
                );
                widget.form.customerTermDirty = true;
                widget.onChanged();
                setState(() {});
              },
            ),
            _date(
              customerChangeText('termEnd'),
              widget.form.definition.termEndAt,
              (v) {
                widget.form.definition = widget.form.definition.copyWith(
                  termEndAt: v,
                );
                widget.form.customerTermDirty = true;
                widget.onChanged();
                setState(() {});
              },
            ),
            for (final op in ['cancel', 'move']) _operation(op),
            if (_error != null)
              Semantics(
                liveRegion: true,
                child: Text(customerChangeText(_error!)),
              ),
          ],
        ),
      ),
    ],
  );
}
