import 'package:flutter/material.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import '../occasion_sale_strings.dart';
import 'occasion_setup_story.dart';

/// Creation intent only. Finalization writes the existing form schedule.
class OccasionSetupSales {
  static String text(Map<String, dynamic> data, String key,
          [Map<String, String>? args]) =>
      OccasionSaleStrings.domainText(
          OccasionSetupStory.hasTickets(data), key, args);
  static String mode(Map<String, dynamic> data) =>
      data['saleMode'] as String? ?? 'preparation';
  static DateTime? start(Map<String, dynamic> data) =>
      DateTime.tryParse(data['saleStart'] as String? ?? '');
  static DateTime? end(Map<String, dynamic> data) =>
      DateTime.tryParse((data['saleEnd'] ?? data['end']) as String? ?? '');
  static bool valid(Map<String, dynamic> data, DateTime now) {
    if (data['formEnabled'] == false) return true;
    final kind = mode(data);
    final finish = end(data);
    final occasionEnd = DateTime.tryParse(data['end'] as String? ?? '');
    if (!const ['preparation', 'scheduled', 'immediate'].contains(kind) ||
        finish == null ||
        occasionEnd == null ||
        finish.isAfter(occasionEnd)) return false;
    if (kind == 'scheduled') {
      final begin = start(data);
      return begin != null && begin.isAfter(now) && begin.isBefore(finish);
    }
    return kind != 'immediate' || finish.isAfter(now);
  }

  static String createLabel(Map<String, dynamic> data) => text(
      data,
      data['formEnabled'] == false
          ? 'create'
          : switch (mode(data)) {
              'scheduled' => 'createScheduled',
              'immediate' => 'createOpen',
              _ => 'create'
            });
}

class OccasionSetupSaleSettings extends StatelessWidget {
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;
  const OccasionSetupSaleSettings(
      {super.key, required this.data, required this.onChanged});

  Widget _term(
      BuildContext context, String key, String label, DateTime? fallback) {
    final raw = DateTime.tryParse(data[key] as String? ?? '');
    final value = raw?.toOccasionTime() ?? fallback;
    void update(DateTime next) =>
        onChanged({key: next.toUtcFromOccasionTime().toIso8601String()});
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: Theme.of(context).textTheme.titleSmall),
          TimeDatePicker(
              date: value,
              time: value == null ? null : TimeOfDay.fromDateTime(value),
              dateLabel: label,
              timeLabel: OccasionSetupSales.text(data, 'time'),
              minDate: DateTime(2000),
              maxDate: DateTime(2101),
              onDateChanged: (d) => update(DateTime(d.year, d.month, d.day,
                  value?.hour ?? 18, value?.minute ?? 0)),
              onTimeChanged: (t) {
                final d = value ?? DateTime.now();
                update(DateTime(d.year, d.month, d.day, t.hour, t.minute));
              }),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final kind = OccasionSetupSales.mode(data);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RadioGroup<String>(
          groupValue: kind,
          onChanged: (value) {
            if (value != null) {
              onChanged({
                'saleMode': value,
                if (value == 'scheduled' && data['saleStart'] == null)
                  'saleStart': DateTime.now()
                      .add(const Duration(hours: 24))
                      .toUtc()
                      .toIso8601String(),
              });
            }
          },
          child: Column(children: [
            for (final option in ['preparation', 'scheduled', 'immediate'])
              RadioListTile<String>(
                  contentPadding: EdgeInsets.zero,
                  value: option,
                  title: Text(OccasionSetupSales.text(data, 'mode.$option')),
                  subtitle:
                      Text(OccasionSetupSales.text(data, 'help.$option'))),
          ])),
      if (kind == 'scheduled')
        _term(context, 'saleStart', OccasionSetupSales.text(data, 'saleStart'),
            null),
      _term(context, 'saleEnd', OccasionSetupSales.text(data, 'saleEnd'),
          DateTime.tryParse(data['end'] as String? ?? '')?.toOccasionTime()),
      const SizedBox(height: 8),
      if (data['saleEnd'] == null)
        Text(OccasionSetupSales.text(data, 'endDefault'))
      else
        TextButton(
            onPressed: () => onChanged({'saleEnd': null}),
            child: Text(OccasionSetupSales.text(data, 'useEventEnd'))),
      CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: data['saleCountdown'] == true,
          onChanged: (value) => onChanged({'saleCountdown': value == true}),
          title: Text(OccasionSetupSales.text(data, 'countdown')),
          subtitle: Text(OccasionSetupSales.text(data, 'countdownHelp'))),
      if (!OccasionSetupSales.valid(data, DateTime.now()))
        Text(OccasionSetupSales.text(data, 'invalidTiming'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
    ]);
  }
}
