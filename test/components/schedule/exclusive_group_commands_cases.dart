import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/schedule/exclusive_group_commands.dart';
import 'package:fstapp/components/schedule/exclusive_group_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('exclusive group save is one versioned aggregate command', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseExclusiveGroupCommands.withTransport(
      null,
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 4,
            'group': {
              'id': 12,
              'title': 'Workshops',
              'exclusive_events': [
                {'event': 7},
                {'event': 8},
              ],
              'aggregate_version': 4,
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final result = await commands.save(
      3,
      ExclusiveGroupModel(
        id: 12,
        title: 'Workshops',
        events: [7, 8],
        aggregateVersion: 3,
      ),
    );

    expect(functionName, 'save_exclusive_group_client_sync_v1');
    expect(parameters['p_expected_version'], 3);
    expect(parameters['p_group'], {
      'id': 12,
      'title': 'Workshops',
      'events': [7, 8],
    });
    expect(result.aggregateVersion, 4);
  });
}
