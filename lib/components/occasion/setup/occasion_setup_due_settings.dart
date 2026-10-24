import 'package:flutter/material.dart';
import 'occasion_setup_strings.dart';

/// Mutates only the setup draft; the owner handles persistence and revisioning.
typedef SetupDraftChange = void Function(void Function(Map<String, dynamic>));

class OccasionSetupDueSettings extends StatefulWidget {
  const OccasionSetupDueSettings(
      {super.key,
      required this.draft,
      required this.onChanged,
      this.inheritedDeadlineSeconds = 604800,
      this.inheritedRemindersEnabled = false,
      this.inheritedReminderSeconds = 86400});

  final Map<String, dynamic> draft;
  final SetupDraftChange onChanged;
  final num inheritedDeadlineSeconds;
  final bool inheritedRemindersEnabled;
  final num inheritedReminderSeconds;

  static bool validDays(String value) {
    final days = num.tryParse(value.replaceAll(',', '.'));
    return days != null && days.isFinite && days >= 0;
  }

  static bool validReminder(Map<String, dynamic> draft,
      {bool inheritedEnabled = false}) {
    final meta = (draft['formDraft'] as Map?)?['data'] as Map? ?? {};
    if ((meta['is_reminder_enabled'] as bool? ?? inheritedEnabled) == false) {
      return true;
    }
    final raw = draft['reminderLeadDays'];
    return raw == null || validDays('$raw');
  }

  static String days(num seconds) =>
      (seconds / 86400).toString().replaceFirst(RegExp(r'\.0$'), '');

  @override
  State<OccasionSetupDueSettings> createState() =>
      _OccasionSetupDueSettingsState();
}

class _OccasionSetupDueSettingsState extends State<OccasionSetupDueSettings> {
  int _reset = 0;
  Map<String, dynamic> get draft => widget.draft;
  SetupDraftChange get onChanged => widget.onChanged;
  num get inheritedDeadlineSeconds => widget.inheritedDeadlineSeconds;
  bool get inheritedRemindersEnabled => widget.inheritedRemindersEnabled;
  num get inheritedReminderSeconds => widget.inheritedReminderSeconds;
  bool validDays(String value) => OccasionSetupDueSettings.validDays(value);
  String days(num seconds) => OccasionSetupDueSettings.days(seconds);

  @override
  Widget build(BuildContext context) {
    final form = draft['formDraft'] as Map? ?? {};
    final data = form['data'] as Map? ?? {};
    final override = form['deadline_duration_seconds'] as num?;
    final deadline = draft['deadlineEdited'] == true
        ? '${draft['deadline'] ?? ''}'
        : days(override ?? inheritedDeadlineSeconds);
    final enabled =
        data['is_reminder_enabled'] as bool? ?? inheritedRemindersEnabled;
    final lead = draft['reminderLeadDays'] as String? ??
        days(data['reminder_interval_seconds'] as num? ??
            inheritedReminderSeconds);
    String t(String key) => OccasionSetupStrings.story(key);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      TextFormField(
        key: ValueKey('${draft['id']}-due-$_reset'),
        initialValue: deadline,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: t('dueDays'),
            suffixText: t('daysAfterOrder'),
            helperText: override == null && draft['deadlineEdited'] != true
                ? t('inheritedSetting')
                : null),
        autovalidateMode: AutovalidateMode.always,
        validator: (value) => validDays(value ?? '') ? null : t('invalidDays'),
        onChanged: (value) => onChanged((next) {
          next['deadline'] = value;
          next['deadlineEdited'] = true;
          if (validDays(value)) {
            (next['formDraft'] as Map)['deadline_duration_seconds'] =
                (num.parse(value.replaceAll(',', '.')) * 86400).round();
          }
        }),
      ),
      if (override != null || draft['deadlineEdited'] == true)
        TextButton(
            onPressed: () {
              setState(() => _reset++);
              onChanged((next) {
                (next['formDraft'] as Map)['deadline_duration_seconds'] = null;
                next['deadlineEdited'] = false;
                next['deadline'] = days(inheritedDeadlineSeconds);
              });
            },
            child: Text(t('restoreDefault'))),
      const SizedBox(height: 8),
      Text(t('cancelUnpaidManually')),
      const SizedBox(height: 16),
      SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(t('remindUnpaid')),
          value: enabled,
          onChanged: (value) => onChanged((next) {
                next['reminders'] = value;
                next['remindersMode'] = value ? 'enabled' : 'disabled';
                final target = next['formDraft'] as Map;
                target['data'] = {
                  ...?target['data'] as Map?,
                  'is_reminder_enabled': value
                };
              })),
      if (enabled) ...[
        TextFormField(
          key: ValueKey('${draft['id']}-reminder-$_reset'),
          initialValue: lead,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
              labelText: t('remindBefore'), suffixText: t('daysBeforeDue')),
          autovalidateMode: AutovalidateMode.always,
          validator: (value) =>
              validDays(value ?? '') ? null : t('invalidDays'),
          onChanged: (value) => onChanged((next) {
            next['reminderLeadDays'] = value;
            if (validDays(value)) {
              final target = next['formDraft'] as Map;
              target['data'] = {
                ...?target['data'] as Map?,
                'reminder_interval_seconds':
                    (num.parse(value.replaceAll(',', '.')) * 86400).round()
              };
            }
          }),
        ),
        if ((num.tryParse(deadline.replaceAll(',', '.')) ?? 0) <=
            (num.tryParse(lead.replaceAll(',', '.')) ?? 0))
          Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(t('shortDeadlineReminder'))),
        if (data.containsKey('reminder_interval_seconds'))
          TextButton(
              onPressed: () {
                setState(() => _reset++);
                onChanged((next) {
                  next.remove('reminderLeadDays');
                  final target = next['formDraft'] as Map;
                  final meta =
                      Map<String, dynamic>.from(target['data'] as Map? ?? {});
                  meta.remove('reminder_interval_seconds');
                  target['data'] = meta;
                });
              },
              child: Text(t('restoreReminderDefault'))),
      ],
    ]);
  }
}
