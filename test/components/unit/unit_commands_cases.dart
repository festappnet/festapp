import '../../support/fixtures/client_command_response_fixture.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/unit/unit_commands.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('unit save carries the unit-scoped aggregate version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseUnitCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return commandResponseFixture(
          params['p_command_id'] as String,
          data: {
            'version': 3,
            'unit': {
              'id': 4,
              'title': 'Unit',
              'data': <String, dynamic>{},
              'aggregate_version': 3,
            },
          },
        );
      }, maxAttempts: 1),
    );

    final saved = await commands.save(
      UnitModel(
        id: 4,
        title: 'Unit',
        data: {'reply_to': 'reply@example.invalid', 'opaque_owner_data': true},
        aggregateVersion: 2,
      ),
    );

    expect(functionName, 'save_unit_client_sync_v1');
    expect(parameters['p_unit'], 4);
    expect(parameters['p_expected_version'], 2);
    expect(saved.aggregateVersion, 3);
    final payload = parameters['p_unit_data'] as Map;
    expect(payload.containsKey('data'), isFalse);
    expect(payload['settings'], {
      'reply_to': 'reply@example.invalid',
      'communication_tone': null,
      'timezone': null,
    });
  });

  test('unit user deletion uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseUnitCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return commandResponseFixture(
          params['p_command_id'] as String,
          data: {'userId': '00000000-0000-0000-0000-000000000001'},
        );
      }, maxAttempts: 1),
    );
    await commands.deleteUserAccess(4, '00000000-0000-0000-0000-000000000001');
    expect(functionName, 'delete_unit_user_client_sync_v1');
  });
}
