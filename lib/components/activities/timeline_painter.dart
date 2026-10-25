// timeline_painter.dart
import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/services/time_helper.dart';

class TimelinePainter extends CustomPainter {
  final DateTime start, end;
  final double pps; // Pixels per second
  final bool isDarkMode;
  // NOTE: Ideally, fetch these from system locale using the `intl` package.
  // Using static English abbreviations for now as per component strings file.
  final List<String> weekdays;
  final List<String> monthAbbreviations;
  final double dateHeaderHeight;
  final double timeTickAreaHeight;

  TimelinePainter({
    required this.start,
    required this.end,
    required this.pps,
    required this.isDarkMode,
    required this.weekdays,
    required this.monthAbbreviations, // Use the list from strings file
    required this.dateHeaderHeight,
    required this.timeTickAreaHeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Paint linePaint = Paint()..strokeWidth = 1.0;
    final TextPainter textPainter = TextPainter(
        textDirection: TextDirection.ltr, textAlign: TextAlign.center);

    final Color primaryTextColor = isDarkMode ? Colors.white : Colors.black87;
    final Color secondaryTextColor =
        isDarkMode ? Colors.white70 : Colors.black54;
    final Color linePrimaryColor = isDarkMode ? Colors.white54 : Colors.black54;
    final Color lineSecondaryColor =
        isDarkMode ? Colors.white38 : Colors.black26;
    final Color lineTertiaryColor =
        isDarkMode ? Colors.white24 : Colors.black12;
    final Color daySeparatorColor =
        isDarkMode ? Colors.blueGrey.shade600 : Colors.blueGrey.shade300;

    // Alternating background colors for the date header
    final Color dayBgColor1 = isDarkMode
        ? Colors.grey.shade800.withOpacity(0.15)
        : Colors.grey.shade200.withOpacity(0.3);
    final Color dayBgColor2 = isDarkMode
        ? Colors.grey.shade800.withOpacity(0.35)
        : Colors.grey.shade200.withOpacity(0.7);

    if (pps <= 0 || start.isAtSameMomentAs(end) || start.isAfter(end)) {
      canvas.drawLine(
          Offset(0, dateHeaderHeight - 0.5),
          Offset(size.width, dateHeaderHeight - 0.5),
          linePaint..color = daySeparatorColor);
      canvas.drawLine(
          Offset(0, dateHeaderHeight + timeTickAreaHeight - 1),
          Offset(size.width, dateHeaderHeight + timeTickAreaHeight - 1),
          linePaint..color = linePrimaryColor);
      return;
    }

    final double calculatedFullLogicalWidth =
        (end.difference(start).inSeconds) * pps;

    // --- 1. Draw Date Header ---
    DateTime currentDayIter =
        DateTime(start.year, start.month, start.day).toOccasionTime();
    double iterDayStartX = 0;
    if (currentDayIter.isBefore(start)) {
      iterDayStartX = 0;
    } else {
      iterDayStartX = currentDayIter.difference(start).inSeconds * pps;
    }

    canvas.save();
    canvas.clipRect(
        Rect.fromLTWH(0, 0, calculatedFullLogicalWidth, dateHeaderHeight));

    int dayCounter = 0;
    while (currentDayIter.isBefore(end)) {
      final bgColor = (dayCounter % 2 == 0) ? dayBgColor1 : dayBgColor2;
      DateTime nextDayIter = currentDayIter.add(const Duration(days: 1));
      double iterDayEndX = nextDayIter.difference(start).inSeconds * pps;
      double effectiveIterDayEndX =
          math.min(iterDayEndX, calculatedFullLogicalWidth);
      double logicalDayWidth = effectiveIterDayEndX - iterDayStartX;

      // Draw alternating background
      canvas.drawRect(
        Rect.fromLTRB(iterDayStartX, 0, effectiveIterDayEndX, dateHeaderHeight),
        Paint()..color = bgColor,
      );

      // --- UPDATED Visually Stronger Label ---
      final dayNameStyle = TextStyle(
          color: primaryTextColor,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          height: 1.0);
      final dayNumberStyle = TextStyle(
          color: secondaryTextColor,
          fontSize: 10,
          fontWeight: FontWeight.normal);

      String dayNameStr = weekdays[currentDayIter.weekday - 1];
      String dateStr =
          "${currentDayIter.day.toString().padLeft(2, '0')}/${currentDayIter.month.toString().padLeft(2, '0')}";

      textPainter.text = TextSpan(
        children: [
          TextSpan(
              text: dayNameStr.toUpperCase(),
              style: dayNameStyle), // Day name on top
          TextSpan(
              text: '\n$dateStr', style: dayNumberStyle), // Number/Month below
        ],
      );
      textPainter.layout();

      final double labelWidth = textPainter.width;
      final double yPosLabel = (dateHeaderHeight - textPainter.height) / 2;
      final double padding = 40.0;
      final double repeatInterval = labelWidth + padding;

      if (logicalDayWidth >= labelWidth) {
        double startX = iterDayStartX + (logicalDayWidth - labelWidth) / 2;
        if (logicalDayWidth < repeatInterval) {
          textPainter.paint(canvas, Offset(startX, yPosLabel));
        } else {
          for (double x = startX;
              x < iterDayEndX - labelWidth;
              x += repeatInterval) {
            if (x + labelWidth > iterDayStartX) {
              textPainter.paint(canvas, Offset(x, yPosLabel));
            }
          }
          for (double x = startX - repeatInterval;
              x > iterDayStartX;
              x -= repeatInterval) {
            if (x < effectiveIterDayEndX) {
              textPainter.paint(canvas, Offset(x, yPosLabel));
            }
          }
        }
      }

      // Day separator line
      if (iterDayStartX > 0) {
        canvas.drawLine(
            Offset(iterDayStartX, 0),
            Offset(iterDayStartX, dateHeaderHeight),
            linePaint..color = daySeparatorColor);
      }

      iterDayStartX = iterDayEndX;
      currentDayIter = nextDayIter;
      dayCounter++;
      if (iterDayStartX >= calculatedFullLogicalWidth &&
          calculatedFullLogicalWidth > 0) break;
    }
    canvas.restore();

    canvas.drawLine(
        Offset(0, dateHeaderHeight - 0.5),
        Offset(calculatedFullLogicalWidth, dateHeaderHeight - 0.5),
        linePaint..color = daySeparatorColor);

    // --- 2. Draw Time Ticks and Labels ---
    final double timeTicksAreaTopY = dateHeaderHeight;
    final double mainLineY = timeTicksAreaTopY + timeTickAreaHeight - 1;
    canvas.drawLine(
        Offset(0, mainLineY),
        Offset(calculatedFullLogicalWidth, mainLineY),
        linePaint..color = linePrimaryColor);

    Duration tickInterval = const Duration(hours: 1);
    bool show30MinTicks = pps * 1800 > 35;
    bool show15MinTicks = pps * 900 > 30;
    bool show5MinTicks = pps * 300 > 25;

    if (show5MinTicks) {
      tickInterval = const Duration(minutes: 5);
    } else if (show15MinTicks)
      tickInterval = const Duration(minutes: 15);
    else if (show30MinTicks) tickInterval = const Duration(minutes: 30);

    DateTime currentTickTime = start.subtract(Duration(
        minutes: start.minute % tickInterval.inMinutes,
        seconds: start.second,
        milliseconds: start.millisecond,
        microseconds: start.microsecond));
    if (currentTickTime.isBefore(start)) {
      currentTickTime = currentTickTime.add(tickInterval);
    }

    canvas.save();
    canvas.clipRect(Rect.fromLTWH(
        0, timeTicksAreaTopY, calculatedFullLogicalWidth, timeTickAreaHeight));

    while (currentTickTime.isBefore(end) ||
        currentTickTime.isAtSameMomentAs(end)) {
      final double dx = currentTickTime.difference(start).inSeconds * pps;
      if (dx >= calculatedFullLogicalWidth + 1 &&
          calculatedFullLogicalWidth > 0) break;

      bool isHourTick = currentTickTime.minute == 0;
      bool isMidnight = isHourTick && currentTickTime.hour == 0;
      bool isHalfHourTick = !isHourTick && currentTickTime.minute == 30;
      bool isQuarterHourTick = !isHourTick &&
          !isHalfHourTick &&
          (currentTickTime.minute == 15 || currentTickTime.minute == 45);

      double tickHeightRatio;
      Color currentTickColor;
      bool drawLabel = false;
      int labelFontSize = 8;
      double textVerticalPadding = 1.5;

      if (isHourTick) {
        tickHeightRatio =
            isMidnight ? 0.40 : (currentTickTime.hour % 6 == 0 ? 0.30 : 0.20);
        currentTickColor = isMidnight ? daySeparatorColor : linePrimaryColor;
        drawLabel = true;
      } else if (show30MinTicks && isHalfHourTick) {
        tickHeightRatio = 0.18;
        currentTickColor = lineSecondaryColor;
        drawLabel = pps * 1800 > 70;
      } else if (show15MinTicks && isQuarterHourTick) {
        tickHeightRatio = 0.12;
        currentTickColor = lineTertiaryColor;
      } else if (show5MinTicks) {
        tickHeightRatio = 0.08;
        currentTickColor = lineTertiaryColor;
      } else {
        currentTickTime = currentTickTime.add(tickInterval);
        continue;
      }

      double actualTickHeight = timeTickAreaHeight * tickHeightRatio;

      if (dx >= -1 && dx <= calculatedFullLogicalWidth + 1) {
        canvas.drawLine(
            Offset(dx, mainLineY),
            Offset(dx, mainLineY - actualTickHeight),
            linePaint..color = currentTickColor);
      }

      if (drawLabel) {
        String labelStr = currentTickTime.hour.toString().padLeft(2, '0');
        if (currentTickTime.minute != 0)
          labelStr += ":${currentTickTime.minute.toString().padLeft(2, '0')}";

        final timeTextPainter = TextPainter(
            text: TextSpan(
                text: labelStr,
                style: TextStyle(
                    color: (isHourTick && currentTickTime.hour == 0)
                        ? primaryTextColor
                        : secondaryTextColor,
                    fontSize: labelFontSize.toDouble())),
            textDirection: TextDirection.ltr);
        timeTextPainter.layout();

        double labelTopY = mainLineY -
            actualTickHeight -
            timeTextPainter.height -
            textVerticalPadding;
        double labelXPos = dx - timeTextPainter.width / 2;

        if (labelTopY < timeTicksAreaTopY)
          labelTopY = timeTicksAreaTopY + textVerticalPadding;

        if (labelXPos + timeTextPainter.width >= -1 &&
            labelXPos <= calculatedFullLogicalWidth + 1) {
          timeTextPainter.paint(canvas, Offset(labelXPos, labelTopY));
        }
      }
      currentTickTime = currentTickTime.add(tickInterval);
      if (dx >= calculatedFullLogicalWidth && calculatedFullLogicalWidth > 0)
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TimelinePainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.pps != pps ||
        oldDelegate.isDarkMode != isDarkMode ||
        !listEquals(
            oldDelegate.weekdays, weekdays) || // Added listEquals for weekdays
        !listEquals(oldDelegate.monthAbbreviations,
            monthAbbreviations) || // Added listEquals for month abbreviations
        oldDelegate.dateHeaderHeight != dateHeaderHeight ||
        oldDelegate.timeTickAreaHeight != timeTickAreaHeight;
  }

  // Helper for shouldRepaint if lists are used
  bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
