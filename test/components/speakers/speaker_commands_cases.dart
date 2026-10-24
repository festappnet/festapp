import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/speakers/speaker_commands.dart';
import 'package:fstapp/components/speakers/speaker_model.dart';
import 'package:fstapp/components/speakers/speaker_topic_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('speaker save owns topic links and carries aggregate version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands =
        SupabaseSpeakerCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 5,
            'speaker': {
              'id': 8,
              'title': 'Ada',
              'order': 0,
              'is_hidden': false,
              'data': <String, dynamic>{},
              'topics': [3, 4],
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final result = await commands.saveSpeaker(
      7,
      SpeakerModel(
        id: 8,
        title: 'Ada',
        topics: [4, 3],
        aggregateVersion: 4,
      ),
    );

    expect(functionName, 'save_speaker_client_sync_v1');
    expect(parameters['p_expected_version'], 4);
    expect((parameters['p_speaker'] as Map)['topics'], [4, 3]);
    expect(result.version, 5);
    expect(result.entity?.topics, [3, 4]);
  });

  test('topic delete and event speakers use statically bound RPCs', () async {
    final calls = <String>[];
    final commands =
        SupabaseSpeakerCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        calls.add(name);
        if (name == 'delete_speaker_topic_client_sync_v1') {
          return {
            'status': 'applied',
            'code': 200,
            'data': {'version': 2, 'topic': null},
            'sync': {'replacements': <Object>[]},
          };
        }
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 10,
            'eventId': 12,
            'speakerIds': [2, 9],
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    await commands.deleteTopic(
      7,
      SpeakerTopicModel(id: 3, title: 'AI', aggregateVersion: 2),
    );
    final event = await commands.saveEventSpeakers(7, 12, 9, [9, 2]);

    expect(calls, [
      'delete_speaker_topic_client_sync_v1',
      'save_event_speakers_client_sync_v1',
    ]);
    expect(event.version, 10);
    expect(event.speakerIds, [2, 9]);
  });

  test('counseling batch commands have dedicated receipt-backed RPCs',
      () async {
    final calls = <String>[];
    final commands =
        SupabaseSpeakerCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        calls.add(name);
        return {
          'status': 'applied',
          'code': 200,
          'data': name.startsWith('create_')
              ? {
                  'created': 2,
                  'event_ids': [21, 22],
                }
              : {'deleted': 2},
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final created = await commands.createCounselingSlots(
      speakerId: 8,
      start: DateTime.utc(2026, 8, 3, 8),
      end: DateTime.utc(2026, 8, 3, 9),
      slotMinutes: 20,
    );
    final deleted = await commands.deleteEmptyCounselingSlots(8);

    expect(calls, [
      'create_counseling_slots_client_sync_v1',
      'delete_empty_counseling_slots_client_sync_v1',
    ]);
    expect(created.eventIds, [21, 22]);
    expect(deleted.count, 2);
  });

  test('single counseling slot deletion uses the guarded slot RPC', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands =
        SupabaseSpeakerCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'eventId': 21, 'deleted': true},
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final result = await commands.deleteCounselingSlot(
      speakerId: 8,
      eventId: 21,
      expectedVersion: 3,
    );

    expect(functionName, 'delete_counseling_slot_client_sync_v1');
    expect(parameters['p_speaker'], 8);
    expect(parameters['p_event_id'], 21);
    expect(parameters['p_expected_version'], 3);
    expect(result.count, 1);
  });
}
