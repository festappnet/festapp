import 'event_model.dart';

typedef _DuplicateKey = ({
  String title,
  DateTime startTime,
  DateTime endTime,
  int? placeId,
});

enum SuspiciousEventReason {
  invalidTiming,
  multiDay,
  outsideOccasion,
  exactDuplicate,
}

class SuspiciousEventDetector {
  static Map<EventModel, List<SuspiciousEventReason>> analyze(
    Iterable<EventModel> events, {
    DateTime? occasionStart,
    DateTime? occasionEnd,
  }) {
    final eventList = events.toList();
    final duplicateCounts = <_DuplicateKey, int>{};

    for (final event in eventList) {
      final key = _duplicateKey(event);
      if (key != null) {
        duplicateCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
      }
    }

    final result = <EventModel, List<SuspiciousEventReason>>{};
    for (final event in eventList) {
      final reasons = <SuspiciousEventReason>[];
      if (!event.endTime.isAfter(event.startTime)) {
        reasons.add(SuspiciousEventReason.invalidTiming);
      } else if (!_isSameDay(event.startTime, event.endTime)) {
        reasons.add(SuspiciousEventReason.multiDay);
      }

      if ((occasionStart != null && event.startTime.isBefore(occasionStart)) ||
          (occasionEnd != null && event.endTime.isAfter(occasionEnd))) {
        reasons.add(SuspiciousEventReason.outsideOccasion);
      }

      final key = _duplicateKey(event);
      if (key != null && (duplicateCounts[key] ?? 0) > 1) {
        reasons.add(SuspiciousEventReason.exactDuplicate);
      }

      if (reasons.isNotEmpty) result[event] = reasons;
    }
    return result;
  }

  static List<EventModel> find(
    Iterable<EventModel> events, {
    DateTime? occasionStart,
    DateTime? occasionEnd,
  }) {
    return analyze(
      events,
      occasionStart: occasionStart,
      occasionEnd: occasionEnd,
    ).keys.toList();
  }

  static bool _isSameDay(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  static _DuplicateKey? _duplicateKey(EventModel event) {
    final title = event.title?.trim().toLowerCase();
    if (title == null || title.isEmpty) return null;

    return (
      title: title,
      startTime: event.startTime,
      endTime: event.endTime,
      placeId: event.place?.id,
    );
  }
}
