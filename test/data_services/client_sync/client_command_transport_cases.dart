import '../../support/fixtures/client_command_response_fixture.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('actor change after an ambiguous failure prevents redispatch', () async {
    var principal = 'original-actor';
    var calls = 0;
    final transport = ClientCommandTransport((_, parameters) async {
      calls++;
      principal = 'different-actor';
      throw TimeoutException('result unknown');
    }, principalProvider: () => principal);

    await expectLater(
      transport.invoke('save_event_client_sync_v1', {},
          commandId: 'b10a0000-0000-4000-8000-000000000001'),
      throwsA(isA<StateError>().having(
          (error) => error.message, 'message', 'COMMAND_PRINCIPAL_CHANGED')),
    );
    expect(calls, 1);
  });

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
      'p_command_id': 'b10a0000-0000-4000-8000-000000000001',
    });

    expect(result, {'status': 'applied'});
    expect(calls, hasLength(2));
    expect(calls.first['p_command_id'], 'b10a0000-0000-4000-8000-000000000001');
    expect(calls.last['p_command_id'], calls.first['p_command_id']);
  });

  test(
    'retry keeps an immutable copy of the original editor baseline',
    () async {
      final request = <String, dynamic>{
        'p_config': {'expected_aggregate_version': 7},
      };
      var calls = 0;
      final transport = ClientCommandTransport((name, parameters) async {
        calls++;
        expect(parameters['p_config']['expected_aggregate_version'], 7);
        if (calls == 1) {
          (request['p_config'] as Map)['expected_aggregate_version'] = 99;
          throw TimeoutException('lost response');
        }
        return {'code': 200};
      });
      await transport.invoke('save_fixture', request);
      expect(calls, 2);
    },
  );

  test('in-memory recovery uses the same validated receipt contract', () async {
    final ids = <String>[];
    var malformed = true;
    final transport = ClientCommandTransport((name, parameters) async {
      final id = parameters['p_command_id'] as String;
      ids.add(id);
      final response = commandResponseFixture(id);
      if (malformed) (response['mutation'] as Map).remove('receiptId');
      return response;
    });
    const request = {'p_occasion': 7, 'p_expected_version': 3};
    await expectLater(
      transport.invokeIntent('fixture', 'save_fixture', request),
      throwsFormatException,
    );
    malformed = false;
    await transport.invokeIntent('fixture', 'save_fixture', request);
    expect(ids.toSet(), hasLength(1));
    await transport.invokeIntent('fixture', 'save_fixture', request);
    expect(ids.last, isNot(ids.first));
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
