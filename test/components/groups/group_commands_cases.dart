import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/group_commands.dart';
import 'package:fstapp/components/groups/group_participant_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('group command sends members and private place as one aggregate',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseGroupCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 4,
            'group': {
              'id': 9,
              'title': 'Team',
              'place': 12,
              'placeData': {
                'id': 12,
                'title': 'Team',
                'type': 'group',
                'is_hidden': true,
                'coordinates': {
                  'latLng': {'lat': 1.0, 'lng': 2.0},
                },
              },
              'participants': <Object>[],
            },
          },
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));
    final group = UserGroupInfoModel(
      id: 9,
      title: 'Team',
      aggregateVersion: 3,
      place: PlaceModel(
        id: 12,
        title: 'Team',
        type: PlaceModel.groupType,
        isHidden: true,
        latLng: {'lat': 1.0, 'lng': 2.0},
      ),
      participants: {
        GroupParticipantModel(
          userInfo: UserInfoModel(id: '00000000-0000-0000-0000-000000000001'),
          isAdmin: true,
        ),
      },
    );

    final result = await commands.save(7, group);

    expect(functionName, 'save_user_group_client_sync_v1');
    expect(parameters['p_expected_version'], 3);
    final dto = parameters['p_group'] as Map;
    expect((dto['privatePlace'] as Map)['id'], 12);
    expect((dto['participants'] as List).single['is_admin'], true);
    expect(result.version, 4);
  });

  test('group assignment import uses the dedicated command', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseGroupCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'mutation': {
            'commandId': params['p_command_id'],
            'receiptId': params['p_command_id'],
            'commitId': null,
            'replayed': false,
            'occurredAt': '2026-10-15T10:00:00Z'
          },
          'status': 'applied',
          'code': 200,
          'data': {'assignments': 1},
          'sync': {'replacements': <Object>[]},
        };
      },
      maxAttempts: 1,
    ));

    await commands.replaceAssignments(
      7,
      {'00000000-0000-0000-0000-000000000001': 'Team'},
    );

    expect(functionName, 'replace_group_assignments_client_sync_v1');
    expect(parameters['p_occasion'], 7);
    expect(parameters['p_assignments'], hasLength(1));
  });
}
