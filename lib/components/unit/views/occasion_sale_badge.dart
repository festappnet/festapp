import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_sale_status.dart';
import 'package:fstapp/components/occasion/occasion_sale_strings.dart';

class OccasionSaleBadge extends StatelessWidget {
  final OccasionModel occasion;
  final OccasionSaleStatus status;
  final DateTime now;
  const OccasionSaleBadge(
      {super.key,
      required this.occasion,
      required this.status,
      required this.now});

  static bool isClosingCountdown(OccasionSaleStatus status, DateTime now) =>
      status.state == OccasionSaleState.selling &&
      status.countdown &&
      status.total == 1 &&
      status.deadline != null &&
      status.deadline!.difference(now).inDays < 3;

  static bool isVisible(OccasionSaleStatus? status, DateTime now) =>
      status != null &&
      status.state != OccasionSaleState.finished &&
      !(status.state == OccasionSaleState.selling &&
          status.active == status.total &&
          status.waitlists == 0 &&
          !isClosingCountdown(status, now));
  @override
  Widget build(BuildContext context) {
    final now = this.now;
    final status = this.status;
    final hasTickets = occasion.saleForms?.any((f) => f.hasTickets) ?? true;
    String wording(String key, [Map<String, String>? args]) =>
        OccasionSaleStrings.domainText(hasTickets, key, args);
    final timezone = occasion.data?[Tb.occasions.data_timezone] as String?;
    final label = OccasionSaleStrings.label(status, now, context.locale,
        timezone: timezone, hasTickets: hasTickets);
    final remaining = status.deadline?.difference(now);
    final closingCountdown = OccasionSaleBadge.isClosingCountdown(status, now);
    final icon = switch (status.state) {
      OccasionSaleState.scheduled => Icons.schedule_outlined,
      OccasionSaleState.selling => closingCountdown
          ? Icons.schedule_outlined
          : status.waitlists > 0
              ? Icons.group_add_outlined
              : Icons.lock_open_outlined,
      OccasionSaleState.waitlist => Icons.group_add_outlined,
      OccasionSaleState.paused => Icons.lock_outline,
      OccasionSaleState.soldOut => Icons.block,
      _ => Icons.lock_outline,
    };
    final count = status.active > 0 && status.total > 1
        ? '${status.active}/${status.total}'
        : null;
    final duration = remaining != null && (status.starts || closingCountdown)
        ? OccasionSaleStrings.duration(remaining, context.locale)
        : null;
    final compactLabel = switch (status.state) {
      OccasionSaleState.scheduled => duration != null
          ? remaining!.inSeconds < 60
              ? wording('startsSoon')
              : wording('shortStartsIn', {'duration': duration})
          : label,
      OccasionSaleState.selling => count ?? duration,
      OccasionSaleState.waitlist => '${wording('waitlist')}'
          '${count == null ? '' : ' $count'}',
      _ => wording(status.state.name),
    };
    final foreground = Theme.of(context).colorScheme.onSurface;
    final detail = [
      wording(status.state.name),
      if (status.total > 1)
        wording('counts', {
          'active': '${status.active}',
          'total': '${status.total}',
          'selling': '${status.selling}',
          'waitlists': '${status.waitlists}'
        }),
      if (status.deadline != null)
        wording(status.starts ? 'startAt' : 'endAt', {
          'date': DateFormat.yMd(context.locale.toLanguageTag())
              .add_jm()
              .format(status.deadline!.toOccasionTime(timezone))
        }),
    ].join('\n');
    return Semantics(
      label: '$label. $detail',
      child: ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IgnoreBaseline(child: Icon(icon, size: 16)),
          if (compactLabel != null) ...[
            const SizedBox(width: 4),
            Flexible(
                child: Text(compactLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground, fontWeight: FontWeight.w500))),
          ],
        ]),
      ),
    );
  }
}
