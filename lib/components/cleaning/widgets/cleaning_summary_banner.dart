import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/styles/styles_config.dart';

/// Top-of-page status summary: calm green "all clean" or an alert pill colored
/// by the most severe open problem, with the problem count.
class CleaningSummaryBanner extends StatelessWidget {
  final List<CleaningPlaceStatus> places;
  const CleaningSummaryBanner({super.key, required this.places});

  @override
  Widget build(BuildContext context) {
    final problems =
        places.where((p) => p.status != CleaningStatus.green).toList();
    final allOk = problems.isEmpty;
    var worst = CleaningStatus.green;
    for (final p in problems) {
      if (p.status.index > worst.index) worst = p.status;
    }
    final accent = CleaningStatusHelper.color(allOk ? CleaningStatus.green : worst);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(StylesConfig.eventItemRoundness),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Row(
        children: [
          Icon(allOk ? Icons.verified_rounded : Icons.warning_amber_rounded,
              color: accent, size: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              allOk
                  ? CleaningStrings.allClean
                  : '${problems.length} · ${CleaningStrings.needsAttention}',
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
        ],
      ),
    );
  }
}
