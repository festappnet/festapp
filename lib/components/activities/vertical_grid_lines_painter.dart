import 'package:material_ui/material_ui.dart';

class VerticalGridLinesPainter extends CustomPainter {
  final DateTime start, end;
  final double pps; // Pixels per second
  final double
      viewHeight; // The height of the area this painter is drawing into (e.g., 24 for activity header, 20 for user row)
  final bool isDarkMode;

  VerticalGridLinesPainter({
    required this.start,
    required this.end,
    required this.pps,
    required this.viewHeight,
    required this.isDarkMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // size.width SHOULD be the full timelineWidth
    final Paint linePaint = Paint();

    // --- MODIFIED COLORS START ---
    final Color daySeparatorColor = isDarkMode
        ? Colors.white.withOpacity(0.4)
        : Colors.black.withOpacity(0.4);

    // Increased opacity for hour lines to make them more distinct
    final Color hourLineColor = isDarkMode
        ? Colors.white.withOpacity(0.18)
        : Colors.black.withOpacity(0.18);
    // Adjusted and standardized opacity for sub-hour lines to make them more subtle
    final Color subHourLineColor = isDarkMode
        ? Colors.white.withOpacity(0.08)
        : Colors.black.withOpacity(0.08);
    // --- MODIFIED COLORS END ---

    if (pps <= 0 || start.isAtSameMomentAs(end) || start.isAfter(end)) {
      // Avoid drawing or errors if parameters are invalid
      return;
    }

    // Determine tick interval based on zoom (pps) - mirrors _TimelinePainter logic for consistency
    Duration tickInterval = const Duration(hours: 1);
    bool show30MinTicks = pps * 1800 > 30; // Thresholds can be fine-tuned
    bool show15MinTicks = pps * 900 > 25;
    bool show5MinTicks = pps * 300 > 20;

    if (show5MinTicks)
      tickInterval = const Duration(minutes: 5);
    else if (show15MinTicks)
      tickInterval = const Duration(minutes: 15);
    else if (show30MinTicks) tickInterval = const Duration(minutes: 30);

    DateTime currentTickTime = start.subtract(Duration(
        // Align to previous tick interval before start
        minutes: start.minute % tickInterval.inMinutes,
        seconds: start.second,
        milliseconds: start.millisecond,
        microseconds: start.microsecond));
    if (currentTickTime.isBefore(start)) {
      // Ensure first tick is at or after start
      currentTickTime = currentTickTime.add(tickInterval);
    }

    // Calculate the full logical width based on the painter's own start, end, and pps.
    final double calculatedFullLogicalWidth =
        (end.difference(start).inSeconds) * pps;

    // Iterate for every tick within the logical start/end of the timeline
    while (currentTickTime.isBefore(end) ||
        currentTickTime.isAtSameMomentAs(end)) {
      final double dx = currentTickTime.difference(start).inSeconds * pps;

      bool isHourTick = currentTickTime.minute == 0;
      bool isMidnight = isHourTick && currentTickTime.hour == 0;
      bool isHalfHourTick = !isHourTick && currentTickTime.minute == 30;
      bool isQuarterHourTick = !isHourTick &&
          !isHalfHourTick &&
          (currentTickTime.minute == 15 || currentTickTime.minute == 45);

      // Determine line style based on tick significance
      if (isMidnight) {
        linePaint.color = daySeparatorColor;
        linePaint.strokeWidth = 0.8;
      } else if (isHourTick) {
        linePaint.color = hourLineColor; // Uses updated hourLineColor
        linePaint.strokeWidth = 0.6;
      } else if (show30MinTicks && isHalfHourTick) {
        linePaint.color = subHourLineColor; // Uses updated subHourLineColor
        linePaint.strokeWidth = 0.5;
      } else if (show15MinTicks && isQuarterHourTick) {
        linePaint.color = subHourLineColor; // Uses updated subHourLineColor
        linePaint.strokeWidth = 0.5;
      } else if (show5MinTicks) {
        // Other 5-minute intervals
        linePaint.color = subHourLineColor; // Uses updated subHourLineColor
        linePaint.strokeWidth = 0.4;
      } else {
        currentTickTime =
            currentTickTime.add(tickInterval); // Move to next potential tick
        if (dx >= calculatedFullLogicalWidth && calculatedFullLogicalWidth > 0)
          break; // Optimization
        continue; // Skip if no display rule matched for this interval
      }

      // Draw ALL logical vertical tick lines at their calculated 'dx'.
      // The underlying canvas (limited by CustomPaint's size) and the parent ClipRect will handle clipping.
      canvas.drawLine(Offset(dx, 0), Offset(dx, viewHeight), linePaint);

      currentTickTime =
          currentTickTime.add(tickInterval); // Advance to the next tick time
      // Optimization: if the current dx is already beyond the calculated full logical width,
      // no need to process further ticks.
      if (dx >= calculatedFullLogicalWidth && calculatedFullLogicalWidth > 0)
        break;
    }
  }

  @override
  bool shouldRepaint(covariant VerticalGridLinesPainter oldDelegate) {
    return oldDelegate.start != start ||
        oldDelegate.end != end ||
        oldDelegate.pps != pps ||
        oldDelegate.viewHeight != viewHeight ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}
