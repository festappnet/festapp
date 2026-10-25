import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';
import 'package:fstapp/components/cleaning/models/cleaning_place_status.dart';
import 'package:fstapp/styles/styles_config.dart';
import 'package:fstapp/theme_config.dart';

class CleaningTile extends StatelessWidget {
  final CleaningPlaceStatus place;
  final void Function(CleaningPlaceStatus) onTap;

  const CleaningTile({super.key, required this.place, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = place.status;
    final isOk = status == CleaningStatus.green;
    final statusColor = CleaningStatusHelper.color(status);
    final biohazard = CleaningStatusHelper.showsBiohazard(status);

    // OK tiles stay calm/neutral so the problem tiles are the ones that pop.
    final bg = isOk
        ? ThemeConfig.qrButtonColor(context)
        : statusColor.withValues(alpha: 0.14);

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(StylesConfig.eventItemRoundness),
        side: BorderSide(
          color: isOk ? Theme.of(context).dividerColor : statusColor,
          width: isOk ? 1 : 2,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(StylesConfig.eventItemRoundness),
        onTap: () => onTap(place),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.wc, size: 19, color: statusColor),
                  const Spacer(),
                  if (biohazard)
                    const Text('☣️', style: TextStyle(fontSize: 15)),
                ],
              ),
              Expanded(
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      place.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
              // Only problem tiles carry a label, so a wall of OK tiles stays
              // clean and scannable when there are many toilets.
              if (!isOk)
                Text(
                  CleaningStrings.statusLabelShort(
                      CleaningStatusHelper.codeOf(status)),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
