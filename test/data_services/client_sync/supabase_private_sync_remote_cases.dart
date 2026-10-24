import 'dart:convert';

import 'package:festapp_core/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/supabase_private_sync_remote.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('private adapter sends the existing scoped RPC and decodes replacement',
      () async {
    final transport = MockClient((request) async {
      expect(request.url.path, '/rest/v1/rpc/get_private_client_sync_v1');
      expect(jsonDecode(request.body), {
        'p_context': {'organizationId': 9, 'occasionId': 643},
        'p_known_private_vector': {'private_program': 4},
      });
      return http.Response(
          jsonEncode({
            'code': 200,
            'data': {
              'serverTime': '2026-10-15T12:00:00Z',
              'vector': {'private_program': 5},
              'components': [
                {
                  'component': 'private_program',
                  'revision': 5,
                  'payload': {
                    'saved': [42]
                  }
                }
              ],
            },
          }),
          200,
          request: request,
          headers: {'content-type': 'application/json'});
    });
    final client = SupabaseClient('https://fixture.invalid', 'fixture',
        httpClient: transport);
    addTearDown(client.dispose);
    final result = await SupabasePrivateSyncRemote(client).getChanges(
      const SyncContext(
          organizationId: 9,
          occasionId: 643,
          occasionLink: 'fixture',
          identityEpoch: 2,
          userId: 'fixture-user'),
      {ClientSyncComponent.privateProgram: 4},
    );
    expect(result.vector[ClientSyncComponent.privateProgram], 5);
    expect(result.replacements.single.payload, {
      'saved': [42]
    });
  });

  test('private adapter rejects public data in a private response', () async {
    final client = SupabaseClient('https://fixture.invalid', 'fixture',
        httpClient: MockClient((request) async => http.Response(
            jsonEncode({
              'code': 200,
              'data': {
                'serverTime': '2026-10-15T12:00:00Z',
                'vector': {'live_public': 5},
                'components': []
              },
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'})));
    addTearDown(client.dispose);
    await expectLater(
        SupabasePrivateSyncRemote(client).getChanges(
          const SyncContext(
              organizationId: 9,
              occasionId: 643,
              occasionLink: 'fixture',
              identityEpoch: 2,
              userId: 'fixture-user'),
          {},
        ),
        throwsFormatException);
  });
}
