import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/features/feature.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/counseling_feature.dart';
import 'package:fstapp/components/speakers/counseling_availability.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speakers_bundle.dart';

void main() {
  group('SpeakersBundle.fromJson', () {
    final bundle = SpeakersBundle.fromJson({
      'speakers': [
        {'id': 1, 'title': 'A', 'subtitle': 'knez', 'order': 0},
        {'id': 2, 'title': 'B', 'order': 1},
      ],
      'speaker_topics': [
        {'id': 10, 'title': 'Rodina', 'order': 0},
        {'id': 11, 'title': 'Uzkosti', 'order': 1},
      ],
      'speaker_topic_links': [
        {'speaker': 1, 'topic': 10},
        {'speaker': 1, 'topic': 11},
        {'speaker': 2, 'topic': 10},
      ],
      'event_speakers': [
        {'event': 100, 'speaker': 1},
        {'event': 100, 'speaker': 2},
        {'event': 101, 'speaker': 2},
      ],
    });

    test('parses speakers and topics', () {
      expect(bundle.speakers.length, 2);
      expect(bundle.topics.length, 2);
      expect(bundle.speakerById(1)!.subtitle, 'knez');
    });

    test('builds bidirectional topic links', () {
      expect(bundle.topicsBySpeaker[1], containsAll([10, 11]));
      expect(bundle.speakersByTopic[10], containsAll([1, 2]));
      expect(bundle.speakersByTopic[11], [1]);
    });

    test('speakersForEvent resolves attached speakers in order', () {
      final onEvent = bundle.speakersForEvent(100).map((s) => s.id).toList();
      expect(onEvent, [1, 2]);
      expect(bundle.speakersForEvent(101).map((s) => s.id).toList(), [2]);
      expect(bundle.speakersForEvent(999), isEmpty);
    });

    test('round-trips through toJson', () {
      final again = SpeakersBundle.fromJson(bundle.toJson());
      expect(again.speakers.length, 2);
      expect(again.speakersByTopic[10], containsAll([1, 2]));
      expect(again.speakersByEvent[100], containsAll([1, 2]));
    });
  });

  group('SpeakerModel', () {
    test('parses topics and admin event refs with occupancy', () {
      final s = SpeakerModel.fromJson({
        'id': 5,
        'title': 'P. Novak',
        'topics': [10, 11],
        'events': [
          {
            'id': 100,
            'title': 'Slot',
            'max_participants': 1,
            'occupied': 1,
            'is_counseling_slot': true,
          },
        ],
      });
      expect(s.topics, [10, 11]);
      expect(s.events.single.occupied, 1);
      expect(s.events.single.isCounselingSlot, isTrue);
    });

    test('toJson always carries the topics array for atomic replace', () {
      final s = SpeakerModel(id: 5, title: 'X', topics: [10]);
      expect(s.toJson()['topics'], [10]);
      final insert = SpeakerModel(title: 'Y');
      expect(insert.toJson().containsKey('id'), isFalse);
      expect(insert.toJson()['topics'], isEmpty);
    });
  });

  group('CounselingAvailability.fromJson', () {
    test('parses counselors and their slots, full/isSignedIn flags', () {
      final a = CounselingAvailability.fromJson({
        'counselors': [
          {
            'id': 1,
            'title': 'A',
            'slots': [
              {
                'id': 100,
                'max_participants': 1,
                'occupied': 1,
                'isSignedIn': true,
              },
              {
                'id': 101,
                'max_participants': 2,
                'occupied': 1,
                'isSignedIn': false,
              },
            ],
          },
        ],
      });
      final slots = a.counselors.single.slots;
      expect(slots.first.isFull, isTrue);
      expect(slots.first.isSignedIn, isTrue);
      expect(slots.last.isFull, isFalse);
    });
  });

  group('CounselingFeature config', () {
    test('defaults: disabled, type "counseling", limit 1', () {
      final f = CounselingFeature(code: FeatureConstants.counseling);
      expect(f.isEnabled, isFalse);
      expect(f.counselingEventType, FeatureConstants.counselingDefaultEventType);
      expect(f.maxActiveBookings, 1);
    });

    test('fromJson via Feature factory returns a CounselingFeature', () {
      final f = Feature.fromJson({
        FeatureConstants.metaCode: FeatureConstants.counseling,
        FeatureConstants.metaIsEnabled: true,
        FeatureConstants.counselingMaxActiveBookings: 0,
        FeatureConstants.counselingEventType: 'poradna',
      });
      expect(f, isA<CounselingFeature>());
      final cf = f as CounselingFeature;
      expect(cf.isEnabled, isTrue);
      expect(cf.maxActiveBookings, 0);
      expect(cf.counselingEventType, 'poradna');
      expect(cf.toJson()[FeatureConstants.counselingMaxActiveBookings], 0);
    });

    test('toJson round-trips through Feature.fromJson', () {
      final original = CounselingFeature(
        code: FeatureConstants.counseling,
        isEnabled: true,
        counselingEventType: 'poradna',
        maxActiveBookings: 0,
      );
      final again = Feature.fromJson(original.toJson()) as CounselingFeature;
      expect(again.isEnabled, isTrue);
      expect(again.counselingEventType, 'poradna');
      expect(again.maxActiveBookings, 0);
    });

    test('legacy "speakers" code has no special class → SimpleFeature', () {
      // Regression guard: the retired feature code must not resurrect a
      // dedicated class; it decodes as a plain SimpleFeature.
      final f = Feature.fromJson({
        FeatureConstants.metaCode: 'speakers',
        FeatureConstants.metaIsEnabled: true,
      });
      expect(f, isA<SimpleFeature>());
      expect(f, isNot(isA<CounselingFeature>()));
    });
  });
}
