import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_sale_status.dart';
import 'package:fstapp/components/occasion/occasion_sale_strings.dart';

class OccasionSaleBadge extends StatefulWidget {
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
  State<OccasionSaleBadge> createState() => _OccasionSaleBadgeState();
}

class _OccasionSaleBadgeState extends State<OccasionSaleBadge> {
  final _tooltipKey = GlobalKey<TooltipState>();

  @override
  Widget build(BuildContext context) {
    final now = widget.now;
    final status = widget.status;
    final timezone =
        widget.occasion.data?[Tb.occasions.data_timezone] as String?;
    final label = OccasionSaleStrings.label(status, now, context.locale,
        timezone: timezone);
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
              ? OccasionSaleStrings.text('startsSoon')
              : OccasionSaleStrings.text(
                  'shortStartsIn', {'duration': duration})
          : label,
      OccasionSaleState.selling => count ?? duration,
      OccasionSaleState.waitlist => '${OccasionSaleStrings.text('waitlist')}'
          '${count == null ? '' : ' $count'}',
      _ => OccasionSaleStrings.text(status.state.name),
    };
    final foreground = Theme.of(context).colorScheme.onSurface;
    final detail = [
      OccasionSaleStrings.text(status.state.name),
      if (status.total > 1)
        OccasionSaleStrings.text('counts', {
          'active': '${status.active}',
          'total': '${status.total}',
          'selling': '${status.selling}',
          'waitlists': '${status.waitlists}'
        }),
      if (status.deadline != null)
        OccasionSaleStrings.text(status.starts ? 'startAt' : 'endAt', {
          'date': DateFormat.yMd(context.locale.toLanguageTag())
              .add_Hm()
              .format(status.deadline!.toOccasionTime(timezone))
        }),
    ].join('\n');
    return Tooltip(
      key: _tooltipKey,
      excludeFromSemantics: true,
      message: '$label\n$detail',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 8),
      child: TextButton(
        onPressed: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        onFocusChange: (focused) {
          if (focused) _tooltipKey.currentState?.ensureTooltipVisible();
        },
        style: TextButton.styleFrom(
          foregroundColor: foreground,
          backgroundColor: Colors.transparent,
          minimumSize: const Size(44, 44),
          alignment: AlignmentDirectional.centerEnd,
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Semantics(
          label: '$label. $detail',
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16),
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
        ),
      ),
    );
  }
}
