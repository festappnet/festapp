import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/activities/activity_commands.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  test(
      'draft, discard and publish use typed receipt commands including empty graphs',
      () async {
    final calls = <Map<String, dynamic>>[];
    final names = <String>[];
    final commands = SupabaseActivityCommands.withTransport(
        ClientCommandTransport((name, params) async {
      calls.add(params);
      names.add(name);
      return {
        'status': 'applied',
        'code': 200,
        'data': {
          'version': 3,
          'historyId': 9,
          'draftId': 4,
          'latestPublishId': 9
        },
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': '00000000-0000-4000-8000-000000000002',
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': []}
      };
    }));
    await commands.saveDraft(
        occasionId: 7,
        expectedVersion: 2,
        history: {'activities': []},
        parentHistoryId: 8);
    await commands.discardDraft(occasionId: 7, expectedDraftId: 4);
    final result = await commands.publish(
        occasionId: 7,
        expectedVersion: 2,
        activities: [],
        history: {'activities': []},
        parentHistoryId: 8);
    expect(names, [
      'save_activity_draft_client_sync_v1',
      'discard_activity_draft_client_sync_v1',
      'publish_activities_client_sync_v1'
    ]);
    expect(calls.last['p_activities_data'], isEmpty);
    expect(calls[1]['p_expected_draft_id'], 4);
    expect(result.version, 3);
  });
  test('ambiguous publish retry uses original version and UUID', () async {
    final calls = <Map<String, dynamic>>[];
    final commands = SupabaseActivityCommands.withTransport(
        ClientCommandTransport((name, params) async {
      calls.add(params);
      if (calls.length == 1) throw TimeoutException('commit unknown');
      return {
        'status': 'applied',
        'code': 200,
        'data': {'version': 3, 'historyId': 9},
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': '00000000-0000-4000-8000-000000000002',
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': []}
      };
    }, maxAttempts: 1));
    Future<PublishActivitiesResult> save() => commands.publish(
        occasionId: 7,
        expectedVersion: 2,
        activities: [],
        history: {'activities': []},
        parentHistoryId: 8);
    await expectLater(save(), throwsA(isA<TimeoutException>()));
    await save();
    expect(calls.last['p_command_id'], calls.first['p_command_id']);
    expect(calls.last['p_expected_version'], 2);
  });
  test(
      'UTC history and undo preserve instants across DST; restored graph keeps current session clocks',
      () {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Prague'));
    final instant = DateTime.utc(2026, 10, 25, 1, 30);
    final assignment = ActivityAssignmentModel(
        user: null,
        id: '00000000-0000-4000-8000-000000000001',
        activityId: '00000000-0000-4000-8000-000000000002',
        startTime: tz.TZDateTime.from(instant, tz.local),
        endTime: tz.TZDateTime.from(
            instant.add(const Duration(hours: 1)), tz.local));
    final current = EditDataBundle(
        aggregateVersion: 7,
        parentHistoryId: 9,
        id: 10,
        activities: [
          ActivityModel(id: assignment.activityId!, assignments: [assignment])
        ]);
    final history = current.toJsonEditor();
    expect(history['timeBasis'], 'UTC');
    expect(history['activity_assignments'][0]['start_time'],
        '2026-10-25T01:30:00.000Z');
    final restored = EditDataBundle.fromJson(history)
      ..retainSessionFrom(current);
    expect(restored.aggregateVersion, 7);
    expect(restored.parentHistoryId, 9);
    expect(restored.id, 10);
    expect(restored.activityAssignments!.single.startTime!.toUtc(), instant);
  });
}
