import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/information/information_commands.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('game information is one command including its hidden owned data',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands =
        SupabaseInformationCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 1,
            'information': {
              'id': 10,
              'title': 'Checkpoint',
              'type': 'game',
              'is_hidden': false,
              'information_hidden': {
                'id': 11,
                'data': {'correct': 'answer'},
              },
            },
          },
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final result = await commands.save(
      7,
      InformationModel(
        title: 'Checkpoint',
        type: InformationModel.gameType,
        isHidden: false,
        informationHidden: InformationHiddenModel(data: {'correct': 'answer'}),
      ),
    );

    expect(functionName, 'save_information_client_sync_v1');
    expect((parameters['p_information'] as Map)['hiddenData'],
        {'correct': 'answer'});
    expect(result.information?.informationHidden?.id, 11);
    expect(result.version, 1);
  });

  test('game guess uses a receipt-backed private-profile command', () async {
    late String functionName;
    final commands =
        SupabaseInformationCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'domainCode': 200, 'correct': true, 'version': 3},
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-07T10:00:00Z'
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    final result = await commands.guess(11, 'answer');

    expect(functionName, 'game_guess_client_sync_v1');
    expect(result.correct, true);
  });
}
