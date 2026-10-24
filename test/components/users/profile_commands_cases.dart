import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/profile_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('profile save carries target and optimistic version', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseProfileCommands.withTransport(
      ClientCommandTransport(
        (name, params) async {
          functionName = name;
          parameters = params;
          return {
            'status': 'applied',
            'code': 200,
            'data': {'version': 6, 'profile': <String, dynamic>{}},
            'sync': {'replacements': <Object>[]},
          };
        },
        maxAttempts: 1,
      ),
    );
    final profile = OccasionUserModel(
      occasion: 7,
      user: '00000000-0000-0000-0000-000000000001',
      data: {'name': 'Ada'},
      services: <String, dynamic>{},
      aggregateVersion: 5,
    );

    final result = await commands.save(profile);

    expect(functionName, 'save_profile_client_sync_v1');
    expect(parameters['p_user'], profile.user);
    expect(parameters['p_expected_version'], 5);
    expect(result.version, 6);
  });

  test('profile create uses the dedicated atomic command', () async {
    late String functionName;
    final commands = SupabaseProfileCommands.withTransport(
      ClientCommandTransport(
        (name, params) async {
          functionName = name;
          return {
            'status': 'applied',
            'code': 200,
            'data': {
              'version': 1,
              'userId': '00000000-0000-0000-0000-000000000002',
            },
            'sync': {'replacements': <Object>[]},
          };
        },
        maxAttempts: 1,
      ),
    );

    final result = await commands.create(OccasionUserModel(
      occasion: 7,
      data: {'email': 'ada@example.test'},
      services: <String, dynamic>{},
    ));

    expect(functionName, 'create_occasion_user_client_sync_v1');
    expect(result.userId, '00000000-0000-0000-0000-000000000002');
  });

  test('profile delete carries the loaded aggregate version', () async {
    late Map<String, dynamic> parameters;
    final commands = SupabaseProfileCommands.withTransport(
      ClientCommandTransport(
        (name, params) async {
          parameters = params;
          return {
            'status': 'applied',
            'code': 200,
            'data': {'version': 8, 'profile': null},
            'sync': {'replacements': <Object>[]},
          };
        },
        maxAttempts: 1,
      ),
    );
    await commands.delete(OccasionUserModel(
      occasion: 7,
      user: '00000000-0000-0000-0000-000000000001',
      aggregateVersion: 8,
    ));
    expect(parameters['p_expected_version'], 8);
  });

  test('profile import uses the receipt-backed aggregate command', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseProfileCommands.withTransport(
      ClientCommandTransport(
        (name, params) async {
          functionName = name;
          parameters = params;
          return {
            'status': 'applied',
            'code': 200,
            'data': {'created': 1, 'updated': 0, 'deleted': 0},
            'sync': {'replacements': <Object>[]},
          };
        },
        maxAttempts: 1,
      ),
    );

    await commands.importProfiles(7, [
      {
        'data': {'email': 'ada@example.test'},
      }
    ], const []);

    expect(functionName, 'import_profiles_client_sync_v1');
    expect(parameters['p_occasion'], 7);
    expect(parameters['p_rows'], hasLength(1));
  });

  test('ticket profile import uses its dedicated command', () async {
    late String functionName;
    final commands = SupabaseProfileCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'code': 200,
            'data': {'inserted': <Object>[]},
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final result = await commands.importFromTickets(7);
    expect(functionName, 'import_users_from_tickets_client_sync_v1');
    expect(result['code'], 200);
  });

  test('membership ensure uses its dedicated command', () async {
    late String functionName;
    final commands = SupabaseProfileCommands.withTransport(
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
    await commands.ensureMembership(
      7,
      '00000000-0000-0000-0000-000000000001',
    );
    expect(functionName, 'add_user_to_occasion_client_sync_v1');
  });
}
