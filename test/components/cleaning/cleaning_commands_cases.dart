import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/cleaning/cleaning_commands.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('report command is statically bound and carries its aggregate key',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseCleaningCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'duplicate': false, 'id': 11},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    final result = await commands.report(
      placeId: 9,
      problemType: 'paper',
      note: 'empty',
    );

    expect(functionName, 'report_cleaning_issue_client_sync_v1');
    expect(parameters['p_place'], 9);
    expect(parameters['p_problem_type'], 'paper');
    expect(result.data['id'], 11);
  });

  test('preference command has a dedicated RPC', () async {
    late String functionName;
    final commands = SupabaseCleaningCommands.withTransport(
      ClientCommandTransport((name, params) async {
        functionName = name;
        return {
          'status': 'unchanged',
          'code': 200,
          'data': {'muted': true},
          'sync': {'replacements': <Object>[]},
        };
      }, maxAttempts: 1),
    );

    await commands.setNotificationsMuted(7, true);

    expect(functionName, 'set_cleaning_notifications_muted_client_sync_v1');
  });
}
