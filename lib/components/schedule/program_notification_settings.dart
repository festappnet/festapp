import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/schedule/schedule_strings.dart';
import 'package:fstapp/theme_config.dart';

class ProgramNotificationSettingsCard extends StatefulWidget {
  const ProgramNotificationSettingsCard({super.key});

  @override
  State<ProgramNotificationSettingsCard> createState() =>
      _ProgramNotificationSettingsCardState();
}

class _ProgramNotificationSettingsCardState
    extends State<ProgramNotificationSettingsCard> {
  static const _leadTimeOptions = [10, 15, 30, 60];

  bool _isEnabled = false;
  int _leadMinutes = 15;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.notifications_active_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    ScheduleStrings.programRemindersTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              ScheduleStrings.programRemindersDescription,
              style: TextStyle(color: ThemeConfig.grey700(context)),
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(ScheduleStrings.programRemindersToggle),
              value: _isEnabled,
              onChanged: (value) => setState(() => _isEnabled = value),
            ),
            AnimatedOpacity(
              opacity: _isEnabled ? 1 : 0.45,
              duration: const Duration(milliseconds: 150),
              child: IgnorePointer(
                ignoring: !_isEnabled,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ScheduleStrings.programRemindersLeadTime,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _leadTimeOptions
                          .map(
                            (minutes) => ChoiceChip(
                              label: Text(
                                ScheduleStrings.programRemindersMinutes(
                                  minutes,
                                ),
                              ),
                              selected: _leadMinutes == minutes,
                              onSelected: (_) =>
                                  setState(() => _leadMinutes = minutes),
                            ),
                          )
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
