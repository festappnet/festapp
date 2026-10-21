import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/components/occasion/occasion_sale_status.dart';
import 'package:fstapp/components/occasion/occasion_sale_strings.dart';

class OccasionSaleBadge extends StatefulWidget {
  final OccasionModel occasion;
  const OccasionSaleBadge({super.key, required this.occasion});
  @override
  State<OccasionSaleBadge> createState() => _OccasionSaleBadgeState();
}

class _OccasionSaleBadgeState extends State<OccasionSaleBadge> {
  Timer? _timer;
  final _tooltipKey = GlobalKey<TooltipState>();
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().toUtc();
    final status = OccasionSaleStatus.resolve(widget.occasion.saleForms,
        now: now, occasionEnd: widget.occasion.saleOccasionEndUtc);
    if (status == null) return const SizedBox.shrink();
    final timezone =
        widget.occasion.data?[Tb.occasions.data_timezone] as String?;
    final label = OccasionSaleStrings.label(status, now, context.locale,
        timezone: timezone);
    final remaining = status.deadline?.difference(now);
    final closingCountdown = status.state == OccasionSaleState.selling &&
        status.countdown &&
        status.total == 1 &&
        remaining != null &&
        remaining.inDays < 3;
    // Ordinary open forms and already-grouped past events need no extra signal.
    if (status.state == OccasionSaleState.finished ||
        status.state == OccasionSaleState.selling &&
            status.active == status.total &&
            status.waitlists == 0 &&
            !closingCountdown) {
      return const SizedBox.shrink();
    }
    final icon = switch (status.state) {
      OccasionSaleState.scheduled => Icons.schedule_outlined,
      OccasionSaleState.selling => closingCountdown
          ? Icons.schedule_outlined
          : status.waitlists > 0
              ? Icons.group_add_outlined
              : Icons.lock_open_outlined,
      OccasionSaleState.waitlist => Icons.group_add_outlined,
      OccasionSaleState.paused => Icons.pause,
      OccasionSaleState.soldOut => Icons.block,
      _ => Icons.lock_outline,
    };
    final count = status.active > 0 && status.total > 1
        ? '${status.active}/${status.total}'
        : null;
    final duration = status.countdown &&
            remaining != null &&
            (status.starts || closingCountdown)
        ? OccasionSaleStrings.duration(remaining, context.locale)
        : null;
    final compactLabel = count ?? duration;
    final foreground = Theme.of(context).colorScheme.onSurfaceVariant;
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
          padding: const EdgeInsets.symmetric(horizontal: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Semantics(
          label: '$label. $detail',
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 16),
              if (compactLabel != null) ...[
                const SizedBox(width: 4),
                Text(compactLabel,
                    maxLines: 1,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground, fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
