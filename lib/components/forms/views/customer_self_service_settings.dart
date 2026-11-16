import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';

import '../models/form_editor_draft.dart';
import '../customer_order_changes.dart';
import '../../features/feature_service.dart';
import '../../features/feature_constants.dart';
import '../../features/features_strings.dart';

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
  String? _error;
  bool get _enabled =>
      FeatureService.isFeatureEnabled(FeatureConstants.customerSelfService);
  Map<String, dynamic> get _cancel => _policy.putIfAbsent(
    'cancel',
    () => {
      'enabled': false,
      'mode': 'approval_required',
      'reason_required': false,
      'refund_mode': 'none',
    },
  ) as Map<String, dynamic>;

  void _change() {
    _policy['edit'] = {'enabled': false, 'fields': <dynamic>[]};
    _policy['move'] = {'enabled': false, 'targets': <dynamic>[]};
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
      validator: (v) =>
          required && v == null ? customerChangeText('deadlineRequired') : null,
      builder: (state) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            TimeDatePicker(
              timeLabel: customerChangeText('deadlineTime'),
              dateLabel: customerChangeText('deadlineDate'),
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

  Widget _cancellation() {
    final rule = _cancel;
    final enabled = rule['enabled'] == true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(customerChangeText('cancel')),
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
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    key: ValueKey(_enabled),
    initiallyExpanded: _enabled,
    title: Text(FeaturesStrings.customerSelfServiceTitle),
    subtitle: Text(
      !_enabled
          ? customerChangeText('offHelp')
          : _cancel['enabled'] == true
          ? customerChangeText('configuredHelp')
          : customerChangeText('notConfigured'),
    ),
    children: [
      customerChangesHelp(context),
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_enabled) ...[
              Text(customerChangeText('setupHelp')),
              const SizedBox(height: 12),
            ],
            Text(customerChangeText('cancellationScopeHelp')),
            _cancellation(),
            Text(customerChangeText('answersLocked')),
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
