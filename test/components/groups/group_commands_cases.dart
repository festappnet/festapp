import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/groups/group_commands.dart';
import 'package:fstapp/components/groups/group_participant_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/map/place_model.dart';
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
          'status': 'applied',
          'code': 200,
          'data': {'assignments': 1},
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

    await commands.replaceAssignments(
      7,
      {'00000000-0000-0000-0000-000000000001': 'Team'},
    );

    expect(functionName, 'replace_group_assignments_client_sync_v1');
    expect(parameters['p_occasion'], 7);
    expect(parameters['p_assignments'], hasLength(1));
  });

  test('saved create IDs and place version survive a second save', () async {
    final requests = <Map<String, dynamic>>[];
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, params) async {
      requests.add(params);
      return {
        'status': 'applied',
        'code': 200,
        'data': {
          'version': requests.length,
          'group': {
            'id': 9,
            'title': 'Team',
            'is_admin': true,
            'place': 12,
            'participants': [],
            'placeData': {
              'id': 12,
              'title': 'Private',
              'type': 'group',
              'is_hidden': true,
              'aggregate_version': requests.length,
              'coordinates': {
                'latLng': {'lat': 50.0, 'lng': 14.0}
              }
            }
          }
        },
        'mutation': {
          'commandId': params['p_command_id'],
          'receiptId': params['p_command_id'],
          'commitId': null,
          'replayed': false,
          'occurredAt': '2026-10-07T10:00:00Z'
        },
        'sync': {'replacements': []}
      };
    }));
    final model = UserGroupInfoModel(
        id: null,
        title: 'Team',
        participants: {},
        place: PlaceModel(
            title: 'Private',
            type: 'group',
            isHidden: true,
            latLng: {'lat': 50, 'lng': 14}));
    model.acceptSaved((await commands.save(7, model)).group!);
    expect(model.id, 9);
    expect(model.place?.id, 12);
    expect(model.place?.aggregateVersion, 1);
    await commands.save(7, model);
    expect(requests.last['p_expected_version'], 1);
    expect((requests.last['p_group'] as Map)['id'], 9);
    expect(
        ((requests.last['p_group'] as Map)['privatePlace'] as Map)['id'], 12);
  });

  test('an unloaded participant set cannot erase membership', () async {
    var called = false;
    final commands = SupabaseGroupCommands.withTransport(
        ClientCommandTransport((name, params) async {
      called = true;
      return null;
    }));
    await expectLater(
        commands.save(
            7, UserGroupInfoModel(id: 9, title: 'Team', participants: null)),
        throwsStateError);
    expect(called, false);
  });
}
