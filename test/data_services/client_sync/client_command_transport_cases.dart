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
}
