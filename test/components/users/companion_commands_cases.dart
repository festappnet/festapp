import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/companion/companion_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('companion create uses the typed command and applies its result',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseCompanionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'companion': {
              'id': '10000000-0000-0000-0000-000000000001',
              'name': 'Alex',
              'event_ids': <int>[],
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final result = await commands.createSelf(9, 'Alex');

    expect(functionName, 'create_companion_client_sync_v1');
    expect(parameters['p_occasion'], 9);
    expect(parameters['p_name'], 'Alex');
    expect(result.name, 'Alex');
  });

  test('admin assignment uses explicit owner and companion parameters',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseCompanionCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': <String, dynamic>{},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.assignExisting(9, 'owner', 'companion');

    expect(functionName, 'assign_existing_companion_client_sync_v1');
    expect(parameters, containsPair('p_owner', 'owner'));
    expect(parameters, containsPair('p_companion', 'companion'));
  });
}
