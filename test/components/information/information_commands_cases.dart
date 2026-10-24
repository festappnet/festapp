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

  test('unit quote preserves its original baseline without an occasion scope',
      () async {
    final commands = SupabaseInformationCommands.withTransport(
        ClientCommandTransport((name, params) async {
      expect(name, 'save_unit_information_client_sync_v1');
      expect(params['p_unit'], 7);
      expect(params.containsKey('p_occasion'), false);
      expect(params['p_expected_version'], 3);
      return {
        'status': 'applied',
        'code': 200,
        'data': {
          'version': 4,
          'information': {'id': 11, 'unit': 7, 'type': 'quote'}
        },
        'sync': {'replacements': <Object>[]}
      };
    }, maxAttempts: 1));
    final result = await commands.save(99,
        InformationModel(id: 11, unit: 7, type: 'quote', aggregateVersion: 3));
    expect(result.information?.unit, 7);
    expect(result.version, 4);
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
