import 'package:timezone/timezone.dart' as tz;
import 'package:test/test.dart';
import 'package:festapp_core/program.dart';

void main() {
  group('event_registration_state', () {
    test(
      'successful registration immediately updates the local event state',
      () {
        final start = DateTime.now();
        final participantsBefore = start.millisecond;
        var event = EventModel(
          startTime: start,
          endTime: start.add(const Duration(hours: 1)),
          currentParticipants: participantsBefore,
          isSignedIn: false,
          timeContext: OccasionTimeContext(tz.UTC),
        );

        event = event.withCurrentUserRegistration(isRegistered: true);

        expect(event.isSignedIn, isTrue);
        expect(event.currentParticipants, participantsBefore + 1);
      },
    );

    group('suspicious timing', () {
      test('accepts an event ending later on the same day', () {
        var event = EventModel(
          startTime: DateTime(2026, 8, 2, 10),
          endTime: DateTime(2026, 8, 2, 11),
          timeContext: OccasionTimeContext(tz.UTC),
        );

        expect(event.hasSuspiciousTiming, isFalse);
      });

      test('flags an event spanning calendar days', () {
        var event = EventModel(
          startTime: DateTime(2026, 8, 2, 23),
          endTime: DateTime(2026, 8, 3, 1),
          timeContext: OccasionTimeContext(tz.UTC),
        );

        expect(event.hasSuspiciousTiming, isTrue);
      });

      test('flags an event whose end is not after its start', () {
        var event = EventModel(
          startTime: DateTime(2026, 8, 2, 11),
          endTime: DateTime(2026, 8, 2, 10),
          timeContext: OccasionTimeContext(tz.UTC),
        );

        expect(event.hasSuspiciousTiming, isTrue);
      });
    });
  });
}
