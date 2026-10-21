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
    final colors = Theme.of(context).colorScheme;
    final selling = status.state == OccasionSaleState.selling;
    final warning = status.state == OccasionSaleState.waitlist ||
        status.state == OccasionSaleState.paused;
    final scheduled = status.state == OccasionSaleState.scheduled;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = selling
        ? (dark ? const Color(0xff224632) : const Color(0xffe6f4ec))
        : warning
            ? (dark ? const Color(0xff513d20) : const Color(0xfffff1d9))
            : scheduled
                ? colors.primaryContainer
                : colors.surfaceContainerHighest;
    final fg = selling
        ? (dark ? const Color(0xffb8e8ca) : const Color(0xff24623b))
        : warning
            ? (dark ? const Color(0xfff2d18e) : const Color(0xff80530c))
            : scheduled
                ? colors.onPrimaryContainer
                : colors.onSurfaceVariant;
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
      message: detail,
      triggerMode: TooltipTriggerMode.tap,
      child: Semantics(
        container: true,
        onTap: () => _tooltipKey.currentState?.ensureTooltipVisible(),
        label: '$label. $detail',
        button: true,
        child: ExcludeSemantics(
            child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Center(
              widthFactor: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(5)),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: fg, fontWeight: FontWeight.w600)),
              )),
        )),
      ),
    );
  }
}
