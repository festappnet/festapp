import 'dart:async';
import 'package:flutter/material.dart';
import 'package:fstapp/components/email_templates/db_email_templates.dart';
import '../occasion_sale_strings.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'occasion_setup_story.dart';
import 'occasion_form_draft.dart';
import 'occasion_setup_details_strings.dart';
import 'occasion_setup_strings.dart';
import 'occasion_setup_email_preview.dart';
import 'occasion_setup_email_templates.dart';

void initializeCommunicationDraft(
  Map<String, dynamic> data, {
  bool reset = false,
}) {
  // A generated starter form is not an explicit communication override.
  final form = data['formDefaultsFollowEvent'] == true
      ? const <String, dynamic>{}
      : (data['formDraft'] as Map?)?['data'] as Map? ?? {};
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

bool communicationDraftValid(
  Map<String, dynamic> data, {
  bool includeReply = true,
  bool includeReminders = true,
}) {
  final email = (data['replyToEmail'] as String? ?? '').trim();
  if (includeReply &&
      data['replyToMode'] == 'custom' &&
      (email.isEmpty ||
          email.length > 254 ||
          FormBuilderValidators.email(errorText: 'invalid')(email) != null))
    return false;
  final lead = (data['reminderLeadDays'] as String? ?? '').trim();
  if (includeReminders &&
      OccasionSetupStory.hasPaidProducts(data) &&
      lead.isNotEmpty) {
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
    (data['reminderLeadDays'] as String? ?? '').replaceAll(',', '.'),
  );
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
  final int? unitId;
  final bool paymentTiming;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final Future<Map<String, dynamic>> Function()? loader;
  final SetupEmailPreviewLoader? loadPreview;
  const OccasionSetupCommunication({
    super.key,
    required this.draftId,
    this.unitId,
    this.paymentTiming = false,
    required this.data,
    required this.onChanged,
    this.loader,
    this.loadPreview,
  });
  @override
  State<OccasionSetupCommunication> createState() =>
      _OccasionSetupCommunicationState();
}

class _OccasionSetupCommunicationState
    extends State<OccasionSetupCommunication> {
  Map<String, dynamic>? _response;
  String? _error;
  bool _loading = true;
  int _fieldRevision = 0;
  bool _senderLoading = false;
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
          : Map<String, dynamic>.from(
              await Supabase.instance.client.rpc(
                'get_occasion_setup_communication',
                params: {'p_id': widget.draftId},
              ),
            );
      if (!mounted) return;
      setState(() {
        _response = result;
        _loading = false;
        _error = null;
      });
      widget.onChanged({'communicationDefaults': result['defaults']});
      if (!widget.paymentTiming &&
          widget.loader == null &&
          (result['defaults'] as Map?)?['replyTo'] == null) {
        unawaited(_resolveSender());
      }
    } catch (_) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = t('communicationLoadFailed');
        });
    }
  }

  Future<void> _resolveSender() async {
    if (_senderLoading) return;
    setState(() => _senderLoading = true);
    try {
      final unitId = widget.unitId;
      if (unitId == null) return;
      final scope =
          await DbEmailTemplates.getEntityEmailTemplates(unitId: unitId);
      final authoring = await DbEmailTemplates.getAuthoringContext(
          scope, 'TICKET_ORDER_CONFIRMATION');
      if (!mounted) return;
      final effective = {...defaults, 'senderAddress': authoring.senderAddress};
      setState(() => _response!['defaults'] = effective);
      widget.onChanged({'communicationDefaults': effective});
    } catch (_) {
      // A missing preview service must not block saving an otherwise valid draft.
      // The UI explicitly reports that the effective address is unavailable.
    } finally {
      if (mounted) setState(() => _senderLoading = false);
    }
  }

  Map<String, dynamic> get defaults =>
      Map<String, dynamic>.from(_response?['defaults'] as Map? ?? {});
  String story(String key) => OccasionSetupStrings.story(key);
  String days(num seconds) =>
      '${seconds / 86400}'.replaceFirst(RegExp(r'\.0$'), '');
  String? validDays(String? value, {bool whole = false}) {
    if ((value ?? '').trim().isEmpty) return null;
    final number = num.tryParse(value!.replaceAll(',', '.'));
    return number == null ||
            !number.isFinite ||
            number < 0 ||
            (whole && int.tryParse(value.trim()) == null)
        ? story('invalidDays')
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final paid = OccasionSetupStory.hasPaidProducts(widget.data);
    final inheritedReply = defaults['replyTo'] ?? defaults['senderAddress'];
    final tone = widget.data['communicationTone'] == 'inherit'
        ? defaults['tone'] ?? 'formal'
        : widget.data['communicationTone'];
    final reminders = widget.data['remindersMode'] == 'enabled' ||
        (widget.data['remindersMode'] == 'inherit' &&
            defaults['remindersEnabled'] != false);
    final deadline = effectiveSetupDeadlineSeconds(widget.data);
    final lead = num.tryParse(
            '${widget.data['reminderLeadDays'] ?? ''}'.replaceAll(',', '.')) ??
        (defaults['leadSeconds'] as num? ?? 86400) / 86400;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) ...[
        Text(_error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextButton(onPressed: _load, child: Text(t('reloadCommunication'))),
      ],
      if (!widget.paymentTiming) ...[
        TextFormField(
          key: const ValueKey('communication-reply'),
          initialValue: widget.data['replyToMode'] == 'custom'
              ? widget.data['replyToEmail'] as String? ?? ''
              : '',
          keyboardType: TextInputType.emailAddress,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
              labelText: t('replyToEmail'),
              hintText: inheritedReply as String?,
              helperText: story('replyToHelp'),
              helperMaxLines: 3),
          validator: (value) => (value ?? '').trim().isEmpty
              ? null
              : (value!.trim().length > 254
                  ? t('invalidReplyEmail')
                  : FormBuilderValidators.email(
                      errorText: t('invalidReplyEmail'))(value.trim())),
          onChanged: (value) => widget.onChanged({
            'replyToMode': value.trim().isEmpty ? 'inherit' : 'custom',
            'replyToEmail': value,
          }),
        ),
        if (widget.data['replyToMode'] != 'custom')
          Text(
              '${t('inheritOrganization')}: ${inheritedReply ?? OccasionSaleStrings.text('senderUnavailable')}'),
        if (inheritedReply == null && widget.data['replyToMode'] != 'custom')
          TextButton.icon(
              onPressed: _senderLoading ? null : _resolveSender,
              icon: const Icon(Icons.refresh),
              label: Text(OccasionSaleStrings.text('retrySender'))),
        const SizedBox(height: 24),
        Text(FormStrings.labelCommunicationTone,
            style: Theme.of(context).textTheme.titleSmall),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final value in ['formal', 'informal'])
            ChoiceChip(
                label: Text(value == 'formal'
                    ? FormStrings.toneFormal
                    : FormStrings.toneInformal),
                selected: tone == value,
                onSelected: (_) =>
                    widget.onChanged({'communicationTone': value})),
        ]),
        if (widget.data['communicationTone'] == 'inherit')
          Text(story('inheritedSetting'))
        else
          TextButton(
              onPressed: () =>
                  widget.onChanged({'communicationTone': 'inherit'}),
              child: Text(story('restoreDefault'))),
        if (widget.loadPreview != null) ...[
          const SizedBox(height: 24),
          OccasionSetupEmailTemplates(
              draft: widget.data,
              loadPreview: widget.loadPreview!,
              onChanged: widget.onChanged),
        ],
      ],
      if (paid && widget.paymentTiming) ...[
        TextFormField(
          key: ValueKey('deadline-$_fieldRevision'),
          initialValue: (widget.data['deadline'] as String? ?? '').isEmpty
              ? days(deadline)
              : widget.data['deadline'] as String,
          keyboardType: TextInputType.number,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(labelText: FormStrings.labelDeadlineDays),
          validator: (value) => validDays(value, whole: true),
          onChanged: (value) => widget.onChanged({'deadline': value}),
        ),
        if ((widget.data['deadline'] as String? ?? '').isNotEmpty)
          TextButton(
              onPressed: () {
                widget.onChanged({'deadline': ''});
                setState(() => _fieldRevision++);
              },
              child: Text(story('restoreDefault')))
        else
          Text(story('inheritedSetting')),
        const SizedBox(height: 8),
        Text(story('cancelUnpaidManually')),
        const SizedBox(height: 16),
        SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: Text(t('paymentReminders')),
            value: reminders,
            onChanged: (value) => widget
                .onChanged({'remindersMode': value ? 'enabled' : 'disabled'})),
        if (widget.data['remindersMode'] != 'inherit')
          TextButton(
              onPressed: () => widget.onChanged({'remindersMode': 'inherit'}),
              child: Text(story('restoreDefault'))),
        if (reminders) ...[
          TextFormField(
            key: ValueKey('communication-lead-$_fieldRevision'),
            initialValue: widget.data['reminderLeadDays'] as String? ?? '',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: InputDecoration(
                labelText: t('reminderLeadDays'),
                hintText: days(defaults['leadSeconds'] as num? ?? 86400),
                helperText: t('blankInherits')),
            validator: validDays,
            onChanged: (value) => widget.onChanged({'reminderLeadDays': value}),
          ),
          if (deadline / 86400 <= lead) Text(story('shortDeadlineReminder')),
        ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${t('replyToEmail')}: ${data['replyToMode'] == 'custom' ? data['replyToEmail'] : '$inherited (${defaults['replyTo'] ?? defaults['senderAddress'] ?? OccasionSaleStrings.text('senderUnavailable')})'}',
        ),
        Text(
          '${FormStrings.labelCommunicationTone}: ${data['communicationTone'] == 'inherit' ? '$inherited (${defaults['tone'] == 'informal' ? FormStrings.toneInformal : FormStrings.toneFormal})' : data['communicationTone'] == 'informal' ? FormStrings.toneInformal : FormStrings.toneFormal}',
        ),
        if (OccasionSetupStory.hasPaidProducts(data))
          Text(
            '${t('paymentReminders')}: ${data['remindersMode'] == 'inherit' ? '$inherited (${defaults['remindersEnabled'] == false ? FormStrings.remindersOff : FormStrings.remindersOn})' : data['remindersMode'] == 'enabled' ? FormStrings.remindersOn : FormStrings.remindersOff}',
          ),
        if (OccasionSetupStory.hasPaidProducts(data) && remindersEnabled)
          Text(
            '${t('reminderLeadDays')}: ${lead.isEmpty ? '$inherited (${(defaults['leadSeconds'] as num? ?? 86400) / 86400})' : lead}',
          ),
      ],
    );
  }
}
