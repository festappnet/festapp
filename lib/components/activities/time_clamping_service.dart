import 'package:material_ui/material_ui.dart';

class TimeClampingService {
  static DateTimeRange clampDateTimeRange({
    required DateTime initialStartTime,
    required Duration itemDuration,
    required DateTime timelineStart,
    required DateTime timelineEnd,
    required Duration minAllowedDuration,
    Duration snapStep =
        const Duration(minutes: 15), // New parameter for snapping
  }) {
    // 1. Clamp initialStartTime to the overall timeline bounds
    DateTime newStart = initialStartTime;
    if (newStart.isBefore(timelineStart)) {
      newStart = timelineStart;
    }
    if (newStart.isAfter(timelineEnd)) {
      newStart = timelineEnd; // This might make newStart > newEnd temporarily
    }

    // 2. Snap newStart to the nearest snapStep
    // Calculate the difference from timelineStart
    final Duration diffFromTimelineStart = newStart.difference(timelineStart);
    // Determine how many snapSteps fit into this duration
    final int numSnapSteps =
        (diffFromTimelineStart.inMicroseconds / snapStep.inMicroseconds)
            .round();
    // Add the snapped duration back to timelineStart
    newStart = timelineStart
        .add(Duration(microseconds: numSnapSteps * snapStep.inMicroseconds));

    // 3. Calculate newEnd based on snapped newStart and itemDuration
    DateTime newEnd = newStart.add(itemDuration);

    // 4. Clamp newEnd to the overall timeline bounds
    if (newEnd.isAfter(timelineEnd)) {
      newEnd = timelineEnd;
      // If newEnd was pushed back, adjust newStart to maintain itemDuration if possible,
      // but ensure it doesn't go before timelineStart.
      if (itemDuration > Duration.zero) {
        DateTime potentialStart = newEnd.subtract(itemDuration);
        newStart = potentialStart.isBefore(timelineStart)
            ? timelineStart
            : potentialStart;
      } else {
        newStart =
            newEnd; // If duration is zero, start and end should be the same
      }
    }

    // 5. Re-snap newStart after potential adjustment from newEnd clamping
    final Duration reDiffFromTimelineStart = newStart.difference(timelineStart);
    final int reNumSnapSteps =
        (reDiffFromTimelineStart.inMicroseconds / snapStep.inMicroseconds)
            .round();
    newStart = timelineStart
        .add(Duration(microseconds: reNumSnapSteps * snapStep.inMicroseconds));
    newEnd = newStart.add(
        itemDuration); // Recalculate newEnd based on the re-snapped newStart

    // 6. Ensure newEnd is within timeline bounds after re-snapping newStart
    if (newEnd.isAfter(timelineEnd)) {
      newEnd = timelineEnd;
    }

    // 7. Handle minimum allowed duration
    Duration currentEffectiveDuration = newEnd.difference(newStart);
    if (minAllowedDuration > Duration.zero &&
        currentEffectiveDuration < minAllowedDuration) {
      DateTime potentialEnd = newStart.add(minAllowedDuration);
      if (potentialEnd.isAfter(timelineEnd)) {
        newEnd = timelineEnd;
        DateTime potentialStart = newEnd.subtract(minAllowedDuration);
        newStart = potentialStart.isBefore(timelineStart)
            ? timelineStart
            : potentialStart;
      } else {
        newEnd = potentialEnd;
      }
    }

    // 8. Final clamping to ensure start <= end and within timeline bounds
    if (newStart.isAfter(newEnd)) {
      newEnd = newStart;
    }
    if (newStart.isBefore(timelineStart)) newStart = timelineStart;
    if (newEnd.isAfter(timelineEnd)) newEnd = timelineEnd;
    if (newEnd.isBefore(timelineStart))
      newEnd = timelineStart; // Should not happen if newStart is clamped
    if (newStart.isAfter(timelineEnd))
      newStart = timelineEnd; // Should not happen if newEnd is clamped

    return DateTimeRange(start: newStart, end: newEnd);
  }
}
