import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/components/schedule/event_model.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // GoTrue initializes its PKCE storage even with session persistence disabled.
  SharedPreferences.setMockInitialValues({});
  tzdata.initializeTimeZones();
  tz.setLocalLocation(tz.getLocation('Europe/Prague'));
  test(
      'event save uses canonical RPC with legacy readers and preserves version and relations',
      () async {
    expect(ClientSyncRuntime.isV1Selected, isFalse);
    late Map<String, dynamic> parameters;
    await Supabase.initialize(
        url: 'https://example.test',
        publishableKey: 'test-key',
        authOptions: const FlutterAuthClientOptions(
            persistSession: false,
            autoRefreshToken: false,
            detectSessionInUri: false),
        httpClient: MockClient((request) async {
          expect(request.method, 'POST');
          expect(request.url.path, '/rest/v1/rpc/save_event_client_sync_v1');
          parameters = jsonDecode(request.body) as Map<String, dynamic>;
          final event = parameters['p_event'] as Map<String, dynamic>;
          return http.Response(
              jsonEncode({
                'status': 'applied',
                'code': 200,
                'data': {'version': 8, 'event': event},
                'mutation': {
                  'commandId': '00000000-0000-4000-8000-000000000001',
                  'receiptId': '00000000-0000-4000-8000-000000000001',
                  'commitId': null,
                  'replayed': false,
                  'occurredAt': '2026-10-07T10:00:00Z'
                },
                'sync': {'replacements': <Object>[]},
              }),
              200,
              headers: {'content-type': 'application/json'},
              request: request);
        }));
    addTearDown(Supabase.instance.dispose);
    final result = await DbEvents.updateEvent(EventModel(
      id: 3,
      occasionId: 1,
      aggregateVersion: 7,
      startTime: DateTime.utc(2024, 10, 1, 9),
      endTime: DateTime.utc(2024, 10, 1, 10),
      title: 'Edited event',
      description: '<p>Edited description</p>',
      parentEventIds: [6, 4],
      eventRolesIds: [9, 2],
    ));
    expect(parameters['p_expected_version'], 7);
    expect(parameters['p_occasion'], 1);
    expect(parameters['p_command_id'], isNotEmpty);
    expect(parameters['p_event']['parentEventIds'], [4, 6]);
    expect(parameters['p_event']['eventRoleIds'], [2, 9]);
    expect(result.aggregateVersion, 8);
    expect(result.description, '<p>Edited description</p>');
    expect(result.parentEventIds, [4, 6]);
  });
}
