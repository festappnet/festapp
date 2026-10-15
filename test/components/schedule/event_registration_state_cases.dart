import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/event_model.dart';

void main() {
  test('successful registration immediately updates the local event state', () {
    final start = DateTime.now();
    final participantsBefore = start.millisecond;
    final event = EventModel(
      startTime: start,
      endTime: start.add(const Duration(hours: 1)),
      currentParticipants: participantsBefore,
      isSignedIn: false,
    );

    event.updateCurrentUserRegistration(isRegistered: true);

    expect(event.isSignedIn, isTrue);
    expect(event.currentParticipants, participantsBefore + 1);
  });

  group('suspicious timing', () {
    test('accepts an event ending later on the same day', () {
      final event = EventModel(
        startTime: DateTime(2026, 8, 2, 10),
        endTime: DateTime(2026, 8, 2, 11),
      );

      expect(event.hasSuspiciousTiming, isFalse);
    });

    test('flags an event spanning calendar days', () {
      final event = EventModel(
        startTime: DateTime(2026, 8, 2, 23),
        endTime: DateTime(2026, 8, 3, 1),
      );

      expect(event.hasSuspiciousTiming, isTrue);
    });

    test('flags an event whose end is not after its start', () {
      final event = EventModel(
        startTime: DateTime(2026, 8, 2, 11),
        endTime: DateTime(2026, 8, 2, 10),
      );

      expect(event.hasSuspiciousTiming, isTrue);
    });
  });
}
