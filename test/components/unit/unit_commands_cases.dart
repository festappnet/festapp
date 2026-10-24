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
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 3,
            'unit': {
              'id': 4,
              'title': 'Unit',
              'data': <String, dynamic>{},
              'aggregate_version': 3,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final saved = await commands.save(UnitModel(
      id: 4,
      title: 'Unit',
      data: <String, dynamic>{},
      aggregateVersion: 2,
    ));

    expect(functionName, 'save_unit_client_sync_v1');
    expect(parameters['p_unit'], 4);
    expect(parameters['p_expected_version'], 2);
    expect(saved.aggregateVersion, 3);
  });

  test('unit user deletion uses its dedicated command RPC', () async {
    late String functionName;
    final commands = SupabaseUnitCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'userId': '00000000-0000-0000-0000-000000000001'},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );
    await commands.deleteUserAccess(
      4,
      '00000000-0000-0000-0000-000000000001',
    );
    expect(functionName, 'delete_unit_user_client_sync_v1');
  });
}
