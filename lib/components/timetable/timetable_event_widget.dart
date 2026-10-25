import 'package:fstapp/components/schedule/event_type_colors.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/timeline/schedule_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:intl/intl.dart';

import 'timetable_controller.dart';

class TimetableEventWidget extends StatefulWidget {
  final TimeBlockItem item;
  final TimetableController controller;

  const TimetableEventWidget({
    super.key,
    required this.item,
    required this.controller,
  });

  @override
  _TimetableEventWidgetState createState() => _TimetableEventWidgetState();
}

class _TimetableEventWidgetState extends State<TimetableEventWidget> {
  @override
  Widget build(BuildContext context) {
    final bool isCancelled = widget.item.isCancelled;
    final bool isUserSpecific = !isCancelled &&
        (widget.item.isInMySchedule || widget.item.isSignedIn());
    final bool isActivity = widget.item.isActivity;

    // --- Strip Style ---
    final double stripWidth = 6.0;
    Color stripColor;
    if (isCancelled) {
      stripColor = Colors.grey;
    } else if (isActivity) {
      stripColor = Theme.of(context).primaryColor;
    } else {
      stripColor = EventTypeColors.background(widget.item.eventType);
    }

    // --- Main Content Background ---
    Color contentBackgroundColor;
    if (isCancelled) {
      contentBackgroundColor = Theme.of(context).brightness == Brightness.dark
          ? Colors.grey.shade800.withOpacity(0.5)
          : Colors.grey.shade300.withOpacity(0.5);
    } else {
      contentBackgroundColor = Theme.of(context).cardColor;
    }

    // --- Border Style ---
    Color borderColor;
    double borderWidth;
    if (isUserSpecific) {
      borderColor = stripColor;
      borderWidth = 1.8;
    } else {
      borderColor = Theme.of(context).dividerColor.withOpacity(0.3);
      borderWidth = 0.5;
    }
    if (isCancelled && isUserSpecific) {
      borderColor = Theme.of(context).dividerColor.withOpacity(0.3);
      borderWidth = 0.5;
    }

    // --- Dimensions Calculation (preserved from original) ---
    final double actualWidth, actualHeight;
    if (widget.controller.isTimeHorizontal) {
      actualWidth = widget.controller
              .timeRangeLength(widget.item.startTime, widget.item.endTime) -
          widget.controller.minimalPadding() * 2;
      actualHeight = widget.controller.itemStaticDimension() -
          widget.controller.minimalPadding() * 2;
    } else {
      actualWidth = widget.controller.itemStaticDimension() -
          widget.controller.minimalPadding() * 2;
      actualHeight = widget.controller
              .timeRangeLength(widget.item.startTime, widget.item.endTime) -
          widget.controller.minimalPadding() * 2;
    }

    if (actualWidth <= 0 || actualHeight <= 0) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: () {
        if (widget.controller.onItemTap != null) {
          widget.controller.onItemTap!(widget.item.id);
        }
      },
      child: Container(
        width: actualWidth,
        height: actualHeight,
        decoration: BoxDecoration(
          color: contentBackgroundColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: borderColor,
            width: borderWidth,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            // --- Colored Strip ---
            Container(
              width: stripWidth,
              color: stripColor,
            ),
            // --- Event Content ---
            Expanded(
              child: widget.controller.isTimeHorizontal
                  ? _buildHorizontalContent(context, isUserSpecific,
                      isCancelled, actualWidth, Theme.of(context).primaryColor)
                  : _buildVerticalContent(context, isUserSpecific, isCancelled,
                      actualHeight, ThemeConfig.blackColor(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalContent(BuildContext context, bool isUserSpecific,
      bool isCancelled, double itemHeight, Color iconColor) {
    final start = widget.item.startTime;
    final end = widget.item.endTime;
    final durationMins = end.difference(start).inMinutes;
    final bool showTimeLabel = durationMins > 20 && itemHeight > 35;

    Color textColor;
    FontWeight fontWeight;
    TextTheme textTheme = Theme.of(context).textTheme;

    if (isCancelled) {
      textColor = Theme.of(context).disabledColor;
      fontWeight = FontWeight.normal;
    } else if (isUserSpecific) {
      textColor = textTheme.bodyLarge?.color ??
          (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black);
      fontWeight = FontWeight.bold;
    } else {
      textColor = textTheme.bodyMedium?.color ??
          (Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : Colors.black87);
      fontWeight = FontWeight.w500;
    }

    Color timeLabelColor = (textTheme.bodySmall?.color ?? Colors.grey)
        .withOpacity(isCancelled ? 0.6 : 0.8);

    const double iconSize = 14.0;
    const double iconTextSpacing = 5.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showTimeLabel)
                Padding(
                  padding: EdgeInsets.only(
                      right:
                          isUserSpecific ? (iconSize + iconTextSpacing) : 0.0),
                  child: Text(
                    '${DateFormat.jm().format(start)} - ${DateFormat.jm().format(end)}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w300,
                      color: timeLabelColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              if (showTimeLabel) const SizedBox(height: 3),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(left: 0.0),
                  child: Text(
                    widget.item.toString(),
                    style: TextStyle(
                      decoration: isCancelled
                          ? TextDecoration.lineThrough
                          : TextDecoration.none,
                      fontSize: 13,
                      fontWeight: fontWeight,
                      color: textColor,
                      height: 1.2,
                    ),
                    overflow: TextOverflow.fade,
                  ),
                ),
              ),
            ],
          ),
          if (isUserSpecific && showTimeLabel)
            Positioned(
              right: 0,
              top: 0,
              child: Icon(
                Icons.check_circle,
                size: iconSize,
                color: iconColor,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHorizontalContent(BuildContext context, bool isUserSpecific,
      bool isCancelled, double itemWidth, Color iconColor) {
    Color textColor;
    FontWeight fontWeight;
    TextTheme textTheme = Theme.of(context).textTheme;

    if (isCancelled) {
      textColor = Theme.of(context).disabledColor;
      fontWeight = FontWeight.normal;
    } else if (isUserSpecific) {
      textColor = textTheme.bodyLarge?.color ??
          (Theme.of(context).brightness == Brightness.dark
              ? Colors.white
              : Colors.black);
      fontWeight = FontWeight.bold;
    } else {
      textColor = textTheme.bodyMedium?.color ??
          (Theme.of(context).brightness == Brightness.dark
              ? Colors.white70
              : Colors.black87);
      fontWeight = FontWeight.w500;
    }

    Widget? userSpecificIconWidget;
    if (isUserSpecific) {
      userSpecificIconWidget = Padding(
        padding: const EdgeInsets.only(right: 5.0),
        child: Icon(
          Icons.check_circle,
          size: 13,
          color: iconColor,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (userSpecificIconWidget != null) userSpecificIconWidget,
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.item.data.toString(),
                style: TextStyle(
                  decoration: isCancelled
                      ? TextDecoration.lineThrough
                      : TextDecoration.none,
                  fontSize: 12,
                  fontWeight: fontWeight,
                  color: textColor,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
