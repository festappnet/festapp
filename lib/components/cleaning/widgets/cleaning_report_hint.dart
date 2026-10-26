import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/styles/styles_config.dart';

/// Calm one-line hint for a plain participant: tap a toilet to report a problem.
/// Keeps the participant view simple (no operational summary / counts).
class CleaningReportHint extends StatelessWidget {
  const CleaningReportHint({super.key});

  @override
  Widget build(BuildContext context) {
    final color = CleaningStatusHelper.color(CleaningStatus.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(StylesConfig.eventItemRoundness),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_outlined, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              CleaningStrings.tapToReport,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
