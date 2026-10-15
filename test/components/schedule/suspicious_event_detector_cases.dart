import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/components/schedule/suspicious_event_detector.dart';

void main() {
  final occasionStart = DateTime(2026, 8, 10);
  final occasionEnd = DateTime(2026, 8, 17);

  EventModel event({
    String title = 'Program',
    DateTime? start,
    DateTime? end,
    int? placeId = 1,
  }) {
    return EventModel(
      title: title,
      startTime: start ?? DateTime(2026, 8, 12, 10),
      endTime: end ?? DateTime(2026, 8, 12, 11),
      place: PlaceModel(
        id: placeId,
        title: 'Place',
        description: null,
        type: null,
      ),
    );
  }

  List<EventModel> detect(List<EventModel> events) =>
      SuspiciousEventDetector.find(
        events,
        occasionStart: occasionStart,
        occasionEnd: occasionEnd,
      );

  test('does not flag a valid unique event inside the occasion', () {
    expect(detect([event()]), isEmpty);
  });

  test('flags every exact duplicate by normalized title, time, and place', () {
    final first = event(title: '  Program ');
    final second = event(title: 'program');

    expect(detect([first, second]), containsAllInOrder([first, second]));
  });

  test('does not flag same-time events at different places', () {
    expect(detect([event(placeId: 1), event(placeId: 2)]), isEmpty);
  });

  test('flags events before or after the occasion', () {
    final before = event(
      start: DateTime(2025, 8, 12, 10),
      end: DateTime(2025, 8, 12, 11),
    );
    final after = event(
      start: DateTime(2027, 8, 12, 10),
      end: DateTime(2027, 8, 12, 11),
    );

    expect(detect([before, after]), containsAllInOrder([before, after]));
  });

  test('flags an event whose end is before its start', () {
    final invalid = event(
      start: DateTime(2026, 8, 12, 11),
      end: DateTime(2026, 8, 12, 10),
    );

    expect(detect([invalid]), [invalid]);
  });

  test('reports every applicable reason for an event', () {
    final first = event(
      title: 'Duplicate',
      start: DateTime(2026, 8, 9, 23),
      end: DateTime(2026, 8, 11, 1),
    );
    final second = event(
      title: 'duplicate',
      start: first.startTime,
      end: first.endTime,
    );

    final analysis = SuspiciousEventDetector.analyze(
      [first, second],
      occasionStart: occasionStart,
      occasionEnd: occasionEnd,
    );

    expect(
      analysis[first],
      [
        SuspiciousEventReason.multiDay,
        SuspiciousEventReason.outsideOccasion,
        SuspiciousEventReason.exactDuplicate,
      ],
    );
  });
}
