import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/widgets/mouse_detector.dart';

/// The time/date row shared by occasion ranges and individual scheduled terms.
/// Keep the date and time separate so callers can validate local wall times.
class TimeDatePicker extends StatelessWidget {
  final DateTime? date;
  final TimeOfDay? time;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<TimeOfDay> onTimeChanged;
  final String? timeLabel, dateLabel;
  final bool enabled, isValid;
  final DateTime? minDate, maxDate;

  const TimeDatePicker({
    super.key,
    required this.date,
    required this.time,
    required this.onDateChanged,
    required this.onTimeChanged,
    this.timeLabel,
    this.dateLabel,
    this.enabled = true,
    this.isValid = true,
    this.minDate,
    this.maxDate,
  });

  @override
  Widget build(BuildContext context) {
    final dateText = date == null
        ? ''
        : DateFormat.yMd(Localizations.localeOf(context).toString())
            .format(date!);
    final timeText = time?.format(context) ?? '';
    return MouseDetector(
        builder: (context, mouseIsConnected) => Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ValueKey('time:$timeText'),
                    initialValue: timeText,
                    enabled: enabled,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: timeLabel ?? CommonStrings.start,
                      labelStyle: TextStyle(
                        color: isValid ? null : ThemeConfig.redColor(context),
                      ),
                    ),
                    onTap: () async {
                      final picked = await TimeHelper.showUniversalTimePicker(
                        context: context,
                        initialTime: time ?? TimeOfDay.now(),
                        initialEntryMode: mouseIsConnected
                            ? TimePickerEntryMode.input
                            : TimePickerEntryMode.dial,
                      );
                      if (picked != null && context.mounted) {
                        onTimeChanged(picked);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    key: ValueKey('date:$dateText'),
                    initialValue: dateText,
                    enabled: enabled,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: dateLabel ?? CommonStrings.startDate,
                      labelStyle: TextStyle(
                        color: isValid ? null : ThemeConfig.redColor(context),
                      ),
                    ),
                    onTap: () async {
                      final first =
                          minDate ?? DateTime.fromMicrosecondsSinceEpoch(0);
                      final last = maxDate ??
                          DateTime.now().add(const Duration(days: 365 * 20));
                      final selected = date ?? DateTime.now();
                      final initial = selected.isBefore(first)
                          ? first
                          : selected.isAfter(last)
                              ? last
                              : selected;
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: initial,
                        firstDate: first,
                        lastDate: last,
                        initialEntryMode: DatePickerEntryMode.calendar,
                      );
                      if (picked != null && context.mounted) {
                        onDateChanged(picked);
                      }
                    },
                  ),
                ),
              ],
            ));
  }
}

class TimeDateRangePicker extends StatelessWidget {
  final DateTime? start;
  final DateTime? end;
  final void Function(DateTime?) onStartChanged;
  final void Function(DateTime?) onEndChanged;
  final bool enabled;
  final DateTime? minDate;
  final DateTime? maxDate;

  TimeDateRangePicker({
    super.key,
    required this.start,
    required this.end,
    required this.onStartChanged,
    required this.onEndChanged,
    this.enabled = true,
    this.minDate,
    this.maxDate,
  });

  void _changeStart(DateTime picked) {
    onStartChanged(picked);
    if (end != null && picked.isAfter(end!)) {
      onEndChanged(DateTime(
          picked.year, picked.month, picked.day, end!.hour, end!.minute));
    }
  }

  void _changeEnd(DateTime picked) {
    onEndChanged(picked);
    if (start != null && picked.isBefore(start!)) {
      onStartChanged(DateTime(
          picked.year, picked.month, picked.day, start!.hour, start!.minute));
    }
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        TimeDatePicker(
          date: start,
          time: start == null ? null : TimeOfDay.fromDateTime(start!),
          enabled: enabled,
          isValid: start != null,
          minDate: minDate,
          maxDate: maxDate,
          onTimeChanged: (picked) {
            final day = start ?? DateTime.now();
            _changeStart(DateTime(
                day.year, day.month, day.day, picked.hour, picked.minute));
          },
          onDateChanged: (picked) => _changeStart(DateTime(
            picked.year,
            picked.month,
            picked.day,
            start?.hour ?? 0,
            start?.minute ?? 0,
          )),
        ),
        const SizedBox(height: 16),
        TimeDatePicker(
          date: end,
          time: end == null ? null : TimeOfDay.fromDateTime(end!),
          timeLabel: CommonStrings.end,
          dateLabel: CommonStrings.endDate,
          enabled: enabled,
          isValid: end != null && start != null && !end!.isBefore(start!),
          minDate: minDate,
          maxDate: maxDate,
          onTimeChanged: (picked) {
            final day = end ?? DateTime.now();
            _changeEnd(DateTime(
                day.year, day.month, day.day, picked.hour, picked.minute));
          },
          onDateChanged: (picked) => _changeEnd(DateTime(
            picked.year,
            picked.month,
            picked.day,
            end?.hour ?? 0,
            end?.minute ?? 0,
          )),
        ),
      ]);
}
