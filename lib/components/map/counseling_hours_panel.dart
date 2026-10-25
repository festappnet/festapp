import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/map/map_page_helper.dart';
import 'package:fstapp/components/map/map_strings.dart';

/// Compact list of counseling availability ranges shown in a place detail.
///
/// Each range is an action because it represents that day's counseling entry
/// point, not merely informational opening hours.
class CounselingHoursPanel extends StatelessWidget {
  final List<CounselingHoursRange> ranges;
  final ValueChanged<CounselingHoursRange> onRangePressed;

  const CounselingHoursPanel({
    required this.ranges,
    required this.onRangePressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final localizations = MaterialLocalizations.of(context);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_outlined, color: colors.onSurface),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  MapStrings.counselingHours,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (var index = 0; index < ranges.length; index++) ...[
            _CounselingHoursAction(
              date: localizations.formatFullDate(ranges[index].start),
              time:
                  '${TimeOfDay.fromDateTime(ranges[index].start).format(context)}–'
                  '${TimeOfDay.fromDateTime(ranges[index].end).format(context)}',
              onPressed: () => onRangePressed(ranges[index]),
            ),
            if (index != ranges.length - 1) const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _CounselingHoursAction extends StatelessWidget {
  final String date;
  final String time;
  final VoidCallback onPressed;

  const _CounselingHoursAction({
    required this.date,
    required this.time,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(10);

    return Semantics(
      button: true,
      label: '$date, $time',
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        date,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        time,
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
