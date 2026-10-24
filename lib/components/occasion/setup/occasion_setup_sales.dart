import 'package:flutter/material.dart';
import 'package:fstapp/widgets/time_data_range_picker.dart';
import 'package:fstapp/services/time_helper.dart';
import 'occasion_setup_strings.dart';

class OccasionSetupSales {
  static bool valid(Map<String, dynamic> d, DateTime now) {
    if (d['formEnabled'] == false ||
        (d['saleMode'] ?? 'preparation') == 'preparation') return true;
    final end = DateTime.tryParse((d['saleEnd'] ?? d['end']) as String? ?? '');
    final occasionEnd = DateTime.tryParse(d['end'] as String? ?? '');
    if (end == null ||
        occasionEnd == null ||
        end.isAfter(occasionEnd) ||
        !end.isAfter(now)) return false;
    if (d['saleMode'] != 'scheduled') return d['saleMode'] == 'immediate';
    final start = DateTime.tryParse(d['saleStart'] as String? ?? '');
    return start != null && start.isAfter(now) && start.isBefore(end);
  }

  static void select(Map<String, dynamic> d, String mode, DateTime now) {
    d['saleMode'] = mode;
    if (mode == 'scheduled')
      d['saleStart'] ??=
          now.add(const Duration(hours: 24)).toUtc().toIso8601String();
  }
}

class OccasionSetupSaleSettings extends StatelessWidget {
  final Map<String, dynamic> draft;
  final void Function(void Function(Map<String, dynamic>)) onChanged;
  const OccasionSetupSaleSettings(
      {super.key, required this.draft, required this.onChanged});
  Widget _term(BuildContext context, String key, String label) {
    final value =
        DateTime.parse((draft[key] ?? draft['end']) as String).toOccasionTime();
    void update(DateTime next) => onChanged(
        (d) => d[key] = next.toUtcFromOccasionTime().toIso8601String());
    return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: TimeDatePicker(
          date: value,
          time: TimeOfDay.fromDateTime(value),
          dateLabel: label,
          timeLabel: OccasionSetupStrings.story('time'),
          minDate: DateTime(2000),
          maxDate: DateTime(2101),
          onDateChanged: (v) => update(
              DateTime(v.year, v.month, v.day, value.hour, value.minute)),
          onTimeChanged: (v) => update(
              DateTime(value.year, value.month, value.day, v.hour, v.minute)),
        ));
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final mode in ['preparation', 'immediate', 'scheduled'])
          RadioListTile<String>(
            value: mode,
            groupValue: draft['saleMode'] as String? ?? 'preparation',
            title: Text(OccasionSetupStrings.story('sale.$mode')),
            onChanged: (value) => onChanged(
                (d) => OccasionSetupSales.select(d, value!, DateTime.now())),
          ),
        if (draft['saleMode'] == 'scheduled')
          _term(context, 'saleStart', OccasionSetupStrings.story('saleStart')),
        if (draft['saleMode'] != null && draft['saleMode'] != 'preparation')
          _term(context, 'saleEnd', OccasionSetupStrings.story('saleEnd')),
        if (!OccasionSetupSales.valid(draft, DateTime.now()))
          Text(OccasionSetupStrings.story('invalidSaleInterval'),
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
      ]);
}
