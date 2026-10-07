import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('transport retry retains the command UUID', () async {
    final calls = <Map<String, dynamic>>[];
    final transport = ClientCommandTransport((name, parameters) async {
      calls.add({...parameters});
      if (calls.length == 1) {
        throw TimeoutException('connection result unknown');
      }
      return {'status': 'applied'};
    });

    final result = await transport.invoke('save_event_client_sync_v1', {
      'p_occasion': 42,
    });

    expect(result, {'status': 'applied'});
    expect(calls, hasLength(2));
    expect(calls.first['p_command_id'], isNotEmpty);
    expect(calls.last['p_command_id'], calls.first['p_command_id']);
  });

  test('non-transport failures are not retried', () async {
    var calls = 0;
    final transport = ClientCommandTransport((name, parameters) async {
      calls++;
      throw StateError('domain response failure');
    });

    await expectLater(
      transport.invoke('save_event_client_sync_v1', {'p_occasion': 42}),
      throwsStateError,
    );
    expect(calls, 1);
  });

  test('ambiguous attempts retain UUID and snapshot across a user retry',
      () async {
    final calls = <Map<String, dynamic>>[];
    final transport = ClientCommandTransport((name, params) async {
      calls.add(params);
      if (calls.length == 1) throw TimeoutException('unknown commit');
      return {
        'status': 'unchanged',
        'code': 200,
        'data': {},
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': []}
      };
    }, maxAttempts: 1);
    final payload = {
      'p_occasion': 7,
      'p_expected_version': 4,
      'graph': {'title': 'Original'}
    };
    await expectLater(transport.invokeIntent('actor:7:group', 'save', payload),
        throwsA(isA<TimeoutException>()));
    await transport.invokeIntent('actor:7:group', 'save', payload);
    expect(calls[0]['p_command_id'], calls[1]['p_command_id']);
    expect(calls[1]['p_expected_version'], 4);
    await transport.invokeIntent('actor:7:group', 'save', payload);
    expect(calls[2]['p_command_id'], isNot(calls[1]['p_command_id']));
  });

  test('double-click shares one immutable request', () async {
    final gate = Completer<Object?>();
    var calls = 0;
    String? commandId;
    final transport = ClientCommandTransport((name, params) {
      commandId = params['p_command_id'];
      calls++;
      return gate.future;
    });
    final first =
        transport.invokeIntent('actor:7:group', 'save', {'p_occasion': 7});
    final second =
        transport.invokeIntent('actor:7:group', 'save', {'p_occasion': 7});
    gate.complete({
      'status': 'unchanged',
      'code': 200,
      'data': {},
      'mutation': {
        'commandId': commandId,
        'receiptId': commandId,
        'commitId': null,
        'replayed': false,
        'occurredAt': '2026-10-07T10:00:00Z'
      },
      'sync': {'replacements': []}
    });
    await Future.wait([first, second]);
    expect(calls, 1);
  });
}
