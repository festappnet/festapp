import 'package:flutter/material.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_commands.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'occasion_setup_story.dart';
import 'occasion_setup_details_strings.dart';

void initializeCommunicationDraft(Map<String, dynamic> data,
    {bool reset = false}) {
  final form = (data['formDraft'] as Map?)?['data'] as Map? ?? {};
  final values = <String, dynamic>{
    'communicationTone':
        ['formal', 'informal'].contains(form['communication_tone'])
            ? form['communication_tone']
            : 'inherit',
    'replyToMode': 'inherit',
    'replyToEmail': '',
    'remindersMode': form['is_reminder_enabled'] is bool
        ? (form['is_reminder_enabled'] == true ? 'inherit' : 'disabled')
        : 'inherit',
    'reminderLeadDays': form['reminder_interval_seconds'] is num
        ? '${(form['reminder_interval_seconds'] as num) / 86400}'
        : '',
  };
  for (final entry in values.entries) {
    if (reset)
      data[entry.key] = entry.value;
    else
      data.putIfAbsent(entry.key, () => entry.value);
  }
}

bool communicationDraftValid(Map<String, dynamic> data) {
  final email = (data['replyToEmail'] as String? ?? '').trim();
  if (data['replyToMode'] == 'custom' &&
      (email.isEmpty ||
          email.length > 254 ||
          FormBuilderValidators.email(errorText: 'invalid')(email) != null))
    return false;
  final lead = (data['reminderLeadDays'] as String? ?? '').trim();
  if (OccasionSetupStory.hasPaidProducts(data) && lead.isNotEmpty) {
    final days = double.tryParse(lead.replaceAll(',', '.'));
    if (days == null || !days.isFinite || days < 0) return false;
  }
  return true;
}

void serializeCommunicationDraft(Map<String, dynamic> data) {
  final form = data['formDraft'];
  if (form is! Map) return;
  final meta = Map<String, dynamic>.from(form['data'] as Map? ?? {});
  if (data['communicationTone'] == 'formal' ||
      data['communicationTone'] == 'informal') {
    meta['communication_tone'] = data['communicationTone'];
  } else {
    meta.remove('communication_tone');
  }
  if (OccasionSetupStory.hasPaidProducts(data) &&
      data['remindersMode'] != 'inherit' &&
      data['remindersMode'] != null) {
    meta['is_reminder_enabled'] = data['remindersMode'] == 'enabled';
  } else {
    meta.remove('is_reminder_enabled');
  }
  final days = double.tryParse(
      (data['reminderLeadDays'] as String? ?? '').replaceAll(',', '.'));
  if (OccasionSetupStory.hasPaidProducts(data) &&
      days != null &&
      days.isFinite &&
      days >= 0) {
    meta['reminder_interval_seconds'] = (days * 86400).round();
  } else {
    meta.remove('reminder_interval_seconds');
  }
  form['data'] = meta;
}

class OccasionSetupCommunication extends StatefulWidget {
  final String draftId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<Map<String, dynamic>> Function()? loader;
  final Future<UnitModel> Function(UnitModel)? saveDefaults;
  const OccasionSetupCommunication(
      {super.key,
      required this.draftId,
      required this.data,
      required this.onChanged,
      this.loader,
      this.saveDefaults});
  @override
  State<OccasionSetupCommunication> createState() =>
      _OccasionSetupCommunicationState();
}

class _OccasionSetupCommunicationState
    extends State<OccasionSetupCommunication> {
  Map<String, dynamic>? _response;
  String? _error;
  bool _loading = true, _saving = false;
  int _fieldRevision = 0;
  String t(String key) => OccasionSetupDetailsStrings.text(key);
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = widget.loader != null
          ? await widget.loader!()
          : Map<String, dynamic>.from(await Supabase.instance.client.rpc(
              'get_occasion_setup_communication',
              params: {'p_id': widget.draftId}));
      if (!mounted) return;
      setState(() {
        _response = result;
        _loading = false;
        _error = null;
      });
      widget.onChanged({'communicationDefaults': result['defaults']});
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = t('communicationLoadFailed');
        });
    }
  }

  Map<String, dynamic> get defaults =>
      Map<String, dynamic>.from(_response?['defaults'] as Map? ?? {});
  bool get _hasOverrides =>
      widget.data['replyToMode'] == 'custom' ||
      ['formal', 'informal'].contains(widget.data['communicationTone']) ||
      (OccasionSetupStory.hasPaidProducts(widget.data) &&
          (['enabled', 'disabled'].contains(widget.data['remindersMode']) ||
              (widget.data['reminderLeadDays'] as String? ?? '').isNotEmpty));
  Future<void> _save() async {
    if (_saving ||
        _response?['canManage'] != true ||
        !communicationDraftValid(widget.data)) return;
    setState(() => _saving = true);
    try {
      final unit = UnitModel.fromJson(
          Map<String, dynamic>.from(_response!['unit'] as Map));
      final patch = Map<String, dynamic>.from(unit.data ?? {});
      if (widget.data['replyToMode'] == 'custom')
        patch['reply_to'] = (widget.data['replyToEmail'] as String).trim();
      if (['formal', 'informal'].contains(widget.data['communicationTone']))
        patch['communication_tone'] = widget.data['communicationTone'];
      if (OccasionSetupStory.hasPaidProducts(widget.data)) {
        if (['enabled', 'disabled'].contains(widget.data['remindersMode']))
          patch['is_reminder_enabled'] =
              widget.data['remindersMode'] == 'enabled';
        final days = double.tryParse(
            (widget.data['reminderLeadDays'] as String? ?? '')
                .replaceAll(',', '.'));
        if (days != null)
          patch['reminder_interval_seconds'] = (days * 86400).round();
      }
      unit.data = patch;
      final saved = widget.saveDefaults != null
          ? await widget.saveDefaults!(unit)
          : await SupabaseUnitCommands(Supabase.instance.client).save(unit);
      if (!mounted) return;
      final current = RightsService.currentUnit();
      if (current?.id == saved.id) {
        current!.data = saved.data;
        current.aggregateVersion = saved.aggregateVersion;
      }
      _fieldRevision++;
      widget.onChanged({
        'replyToMode': 'inherit',
        'communicationTone': 'inherit',
        'remindersMode': 'inherit',
        'reminderLeadDays': ''
      });
      await _load();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t('organizationDefaultsSaved'))));
    } catch (_) {
      if (mounted) setState(() => _error = t('organizationDefaultsFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _choice(String key, String label, Map<String, String> items) =>
      DropdownButtonFormField<String>(
        key: ValueKey('comm-$key-${widget.data[key]}'),
        initialValue: widget.data[key] as String? ?? 'inherit',
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final e in items.entries)
            DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis))
        ],
        onChanged: _saving ? null : (v) => widget.onChanged({key: v}),
      );
  @override
  Widget build(BuildContext context) {
    final paid = OccasionSetupStory.hasPaidProducts(widget.data);
    final tone = defaults['tone'] == 'informal'
        ? FormStrings.toneInformal
        : FormStrings.toneFormal;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading || _saving) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(
            onPressed: _saving ? null : _load,
            child: Text(t('reloadCommunication')))
      ],
      Text(t('inheritCommunicationHint')),
      const SizedBox(height: 20),
      _choice('replyToMode', t('replyToEmail'), {
        'inherit':
            '${t('inheritOrganization')}: ${defaults['replyTo'] ?? t('systemSender')}',
        'custom': t('customForEvent')
      }),
      if (widget.data['replyToMode'] == 'custom')
        TextFormField(
          key: const ValueKey('communication-reply'),
          initialValue: widget.data['replyToEmail'] as String? ?? '',
          enabled: !_saving,
          keyboardType: TextInputType.emailAddress,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(labelText: t('replyToEmail')),
          validator: (value) {
            final email = (value ?? '').trim();
            return email.isEmpty || email.length > 254
                ? t('invalidReplyEmail')
                : FormBuilderValidators.email(
                    errorText: t('invalidReplyEmail'))(email);
          },
          onChanged: (v) => widget.onChanged({'replyToEmail': v}),
        ),
      const SizedBox(height: 20),
      _choice('communicationTone', FormStrings.labelCommunicationTone, {
        'inherit': FormStrings.toneInherit(tone),
        'formal': FormStrings.toneFormal,
        'informal': FormStrings.toneInformal
      }),
      if (paid) ...[
        const SizedBox(height: 20),
        _choice('remindersMode', t('paymentReminders'), {
          'inherit':
              '${t('inheritOrganization')}: ${defaults['remindersEnabled'] == false ? FormStrings.remindersOff : FormStrings.remindersOn}',
          'enabled': FormStrings.remindersOn,
          'disabled': FormStrings.remindersOff
        }),
        if (widget.data['remindersMode'] == 'enabled' ||
            (widget.data['remindersMode'] == 'inherit' &&
                defaults['remindersEnabled'] != false))
          TextFormField(
            key: ValueKey('communication-lead-$_fieldRevision'),
            initialValue: widget.data['reminderLeadDays'] as String? ?? '',
            enabled: !_saving,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                labelText: t('reminderLeadDays'),
                helperText:
                    '${t('blankInherits')}: ${(defaults['leadSeconds'] as num? ?? 86400) / 86400}'),
            onChanged: (v) => widget.onChanged({'reminderLeadDays': v}),
          ),
      ],
      if (_response?['canManage'] == true) ...[
        const SizedBox(height: 24),
        Text(t(_response?['firstEvent'] == true
            ? 'firstEventDefaultsHint'
            : 'organizationDefaultsHint')),
        OutlinedButton.icon(
            onPressed: _saving ||
                    !_hasOverrides ||
                    !communicationDraftValid(widget.data)
                ? null
                : _save,
            icon: const Icon(Icons.domain_outlined),
            label: Text(t('saveOrganizationDefaults'))),
      ],
    ]);
  }
}

class OccasionSetupCommunicationSummary extends StatelessWidget {
  final Map<String, dynamic> data;
  const OccasionSetupCommunicationSummary({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    String t(String k) => OccasionSetupDetailsStrings.text(k);
    final defaults = data['communicationDefaults'] as Map? ?? {};
    final inherited = t('inheritOrganization');
    final lead = (data['reminderLeadDays'] as String? ?? '').trim();
    final remindersEnabled = data['remindersMode'] == 'enabled' ||
        (data['remindersMode'] == 'inherit' &&
            defaults['remindersEnabled'] != false);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          '${t('replyToEmail')}: ${data['replyToMode'] == 'custom' ? data['replyToEmail'] : '$inherited (${defaults['replyTo'] ?? t('systemSender')})'}'),
      Text(
          '${FormStrings.labelCommunicationTone}: ${data['communicationTone'] == 'inherit' ? '$inherited (${defaults['tone'] == 'informal' ? FormStrings.toneInformal : FormStrings.toneFormal})' : data['communicationTone'] == 'informal' ? FormStrings.toneInformal : FormStrings.toneFormal}'),
      if (OccasionSetupStory.hasPaidProducts(data))
        Text(
            '${t('paymentReminders')}: ${data['remindersMode'] == 'inherit' ? '$inherited (${defaults['remindersEnabled'] == false ? FormStrings.remindersOff : FormStrings.remindersOn})' : data['remindersMode'] == 'enabled' ? FormStrings.remindersOn : FormStrings.remindersOff}'),
      if (OccasionSetupStory.hasPaidProducts(data) && remindersEnabled)
        Text(
            '${t('reminderLeadDays')}: ${lead.isEmpty ? '$inherited (${(defaults['leadSeconds'] as num? ?? 86400) / 86400})' : lead}'),
    ]);
  }
}
