import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/theme_config.dart';

/// Small colour legend under the grid.
class CleaningLegend extends StatelessWidget {
  const CleaningLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(String label, CleaningStatus status) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 11,
            height: 11,
            decoration: BoxDecoration(
                color: CleaningStatusHelper.color(status),
                shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, color: ThemeConfig.grey600(context))),
        ],
      );
    }

    return Wrap(
      spacing: 18,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        item(CleaningStrings.statusOk, CleaningStatus.green),
        item(CleaningStrings.shortPaper, CleaningStatus.paper),
        item(CleaningStrings.shortHygiene, CleaningStatus.hygiene),
        item(CleaningStrings.shortContamination, CleaningStatus.contamination),
      ],
    );
  }
}
