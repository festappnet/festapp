import 'dart:async';
import 'package:fstapp/components/occasion/occasion_sale_status.dart';
import 'occasion_sale_badge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/components/eshop/orders_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/forms/form_strings.dart';
import 'package:fstapp/components/occasion/occasion_model.dart';
import 'package:fstapp/services/time_helper.dart';
import 'package:fstapp/styles/styles_config.dart';

import '../../_shared/common_strings.dart';

class OccasionEditCard extends StatefulWidget {
  final OccasionModel occasion;
  final VoidCallback onTap;
  final VoidCallback? onCreateCopy;
  final Color? backgroundColor;
  final String? badge;
  final bool isPresent;
  final bool isAppLanding;
  final VoidCallback? onSetAppLanding;

  const OccasionEditCard({
    super.key,
    required this.occasion,
    required this.onTap,
    this.onCreateCopy,
    this.backgroundColor,
    this.badge,
    this.isPresent = false,
    this.isAppLanding = false,
    this.onSetAppLanding,
  });

  @override
  State<OccasionEditCard> createState() => _OccasionEditCardState();
}

class _OccasionEditCardState extends State<OccasionEditCard> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _syncTimer();
  }

  @override
  void didUpdateWidget(covariant OccasionEditCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTimer();
  }

  void _syncTimer() {
    if (widget.occasion.saleForms?.isNotEmpty != true) {
      _timer?.cancel();
      _timer = null;
    } else {
      // Refresh the sale status as its time window changes.
      _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Builds a single stat widget with an icon, value, and tooltip.
  Widget _buildStat(BuildContext context,
      {required IconData icon,
      required String value,
      required String tooltip}) {
    final theme = Theme.of(context);
    final defaultColor = theme.colorScheme.onSurface.withOpacity(0.7);
    final statsTextStyle =
        theme.textTheme.bodySmall?.copyWith(color: defaultColor);

    return Tooltip(
      message: tooltip,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15.0, color: defaultColor),
          const SizedBox(width: 4.0),
          Text(value, style: statsTextStyle),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final occasion = widget.occasion;
    final now = DateTime.now().toUtc();
    final occasionEnd =
        occasion.saleOccasionEndUtc ?? occasion.endTime?.toUtc();
    final isPast = occasionEnd != null && !now.isBefore(occasionEnd);
    final saleStatus = OccasionSaleStatus.resolve(occasion.saleForms,
        now: now, occasionEnd: occasionEnd);
    final showSaleBadge =
        !isPast && OccasionSaleBadge.isVisible(saleStatus, now);
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final onSurfaceColor = theme.colorScheme.onSurface;

    final cardColor = widget.backgroundColor ??
        (isDarkMode ? Colors.grey[850]! : theme.cardColor);

    // Use a glowing primary color border for present events, otherwise a standard border.
    final borderColor = widget.isPresent
        ? theme.primaryColor
        : (isDarkMode ? Colors.grey[700]! : theme.dividerColor);
    final borderWidth = widget.isPresent ? 2.5 : 1.0;

    return Card(
      elevation: 0,
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StylesConfig.commonRoundness),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InkWell(
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  PopupMenuButton<String>(
                    elevation: 0,
                    icon: Icon(Icons.more_vert,
                        color: onSurfaceColor.withOpacity(0.7)),
                    onSelected: (value) {
                      if (value == "app_landing")
                        widget.onSetAppLanding?.call();
                      if (value == "create_copy") {
                        widget.onCreateCopy?.call();
                      }
                    },
                    itemBuilder: (BuildContext context) => [
                      if (widget.onSetAppLanding != null)
                        PopupMenuItem(
                            value: 'app_landing',
                            child: Text(widget.isAppLanding
                                ? UnitStrings.clearAppLanding
                                : UnitStrings.setAppLanding)),
                      if (widget.onCreateCopy != null)
                        PopupMenuItem(
                          value: "create_copy",
                          child: Text(FormStrings.createCopy),
                        ),
                    ],
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Opacity(
                      key: const ValueKey('occasion-sale-content'),
                      opacity: 1,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Padding(
                            padding: EdgeInsetsDirectional.only(
                                end: showSaleBadge ? 24 : 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                if (occasion.startTime != null &&
                                    occasion.endTime != null)
                                  Expanded(
                                      child: Text(
                                    TimeHelper.getMinimalisticDateRange(context,
                                        occasion.startTime!, occasion.endTime!),
                                    key: const ValueKey('occasion-card-date'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )),
                                if (showSaleBadge) ...[
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: OccasionSaleBadge(
                                        occasion: occasion,
                                        status: saleStatus!,
                                        now: now),
                                  ),
                                ],
                                if (widget.badge != null) ...[
                                  const SizedBox(width: 8),
                                  Badge(
                                      backgroundColor:
                                          theme.colorScheme.primary,
                                      textColor: theme.colorScheme.onPrimary,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      textStyle: theme.textTheme.labelSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                      label: Text(widget.badge!)),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(height: showSaleBadge ? 2 : 4),
                          Tooltip(
                            message: occasion.title ?? '',
                            waitDuration: const Duration(milliseconds: 350),
                            exitDuration: const Duration(milliseconds: 100),
                            showDuration: const Duration(seconds: 8),
                            preferBelow: false,
                            constraints: BoxConstraints(
                              maxWidth:
                                  (MediaQuery.sizeOf(context).width - 32).clamp(
                                0.0,
                                360.0,
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(horizontal: 16),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: theme.colorScheme.outlineVariant,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x24000000),
                                  blurRadius: 16,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            textStyle: theme.textTheme.bodyMedium?.copyWith(
                              color: onSurfaceColor,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                            child: Padding(
                              padding:
                                  const EdgeInsetsDirectional.only(end: 28),
                              child: Text(
                                occasion.title ?? '',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          if (occasion.stats != null) ...[
                            if (FeatureService.isFeatureEnabled(
                                FeatureConstants.form,
                                features: occasion.features)) ...[
                              SizedBox(height: showSaleBadge ? 4 : 8),
                              Builder(builder: (context) {
                                final bool hasTickets =
                                    FeatureService.isFeatureEnabled(
                                        FeatureConstants.ticket,
                                        features: occasion.features);

                                return Wrap(
                                  spacing: 12.0,
                                  runSpacing: 4.0,
                                  children: [
                                    _buildStat(context,
                                        icon: hasTickets
                                            ? Icons.confirmation_number_outlined
                                            : Icons.chat_bubble,
                                        value: (occasion.stats!.total -
                                                occasion.stats!.storno)
                                            .toString(),
                                        tooltip: hasTickets
                                            ? OrdersStrings.tickets
                                            : OrdersStrings.applications),
                                    _buildStat(context,
                                        icon: Icons.check_circle_outline,
                                        value: (occasion.stats!.paidOrSent +
                                                occasion.stats!.used)
                                            .toString(),
                                        tooltip: OrdersStrings.gridPaidOrSent),
                                    _buildStat(context,
                                        icon: Icons.shopping_cart_outlined,
                                        value:
                                            occasion.stats!.ordered.toString(),
                                        tooltip: OrdersStrings.gridOrdered),
                                  ],
                                );
                              })
                            ] else ...[
                              SizedBox(height: showSaleBadge ? 4 : 8),
                              Wrap(
                                spacing: 12.0,
                                runSpacing: 4.0,
                                children: [
                                  _buildStat(context,
                                      icon: Icons.group_outlined,
                                      value: occasion.stats!.users.toString(),
                                      tooltip: CommonStrings.users),
                                ],
                              )
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (widget.isAppLanding)
                    Tooltip(
                        message: UnitStrings.appLanding,
                        child: Icon(Icons.home,
                            semanticLabel: UnitStrings.appLanding,
                            color: theme.colorScheme.primary)),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          PositionedDirectional(
            end: 12,
            top: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Icon(Icons.chevron_right,
                  color: onSurfaceColor.withOpacity(0.5)),
            ),
          ),
        ],
      ),
    );
  }
}
