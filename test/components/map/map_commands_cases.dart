import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/icons/icon_commands.dart';
import 'package:fstapp/components/map/map_commands.dart';
import 'package:fstapp/components/map/db_places.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/path_node.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';

void main() {
  test('place deletion always uses the canonical map command', () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseMapCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {'version': 4, 'place': null},
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

    await DbPlaces.deletePlaceWithCommands(
      commands: commands,
      occasionId: 643,
      place: PlaceModel(id: 522, aggregateVersion: 3, title: 'WC 46'),
    );

    expect(functionName, 'delete_place_client_sync_v1');
    expect(parameters['p_occasion'], 643);
    expect(parameters['p_place_id'], 522);
    expect(parameters['p_expected_version'], 3);
  });

  test('place save always uses the canonical map command', () async {
    late String functionName;
    final commands = SupabaseMapCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 4,
            'place': {...params['p_place'], 'id': 522},
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

    final saved = await DbPlaces.updatePlaceWithCommands(
      commands: commands,
      occasionId: 643,
      place: PlaceModel(
        id: 522,
        aggregateVersion: 3,
        title: 'WC 46',
        latLng: {'lat': 49.83, 'lng': 18.29},
      ),
    );

    expect(functionName, 'save_place_client_sync_v1');
    expect(saved.aggregateVersion, 4);
  });

  test(
      'map editor place decoding preserves versions and rejects forbidden data',
      () {
    final places = DbPlaces.decodeMapEditorPlacesResponse({
      'code': 200,
      'places': [
        {
          'id': 562,
          'title': 'WC 89',
          'coordinates': {
            'latLng': {'lat': 49.8346, 'lng': 18.282},
          },
          'aggregate_version': 2,
        },
      ],
    });

    expect(places.single.aggregateVersion, 2);
    expect(
      () => DbPlaces.decodeMapEditorPlacesResponse({'code': 403}),
      throwsStateError,
    );
  });

  for (final status in [MapCommandStatus.conflict, MapCommandStatus.rejected]) {
    test('place deletion surfaces ${status.name}', () async {
      final commands = _MapCommandsStub(status);

      await expectLater(
        DbPlaces.deletePlaceWithCommands(
          commands: commands,
          occasionId: 643,
          place: PlaceModel(id: 522, aggregateVersion: 3),
        ),
        throwsStateError,
      );
    });
  }

  test('place save is statically bound and carries aggregate version',
      () async {
    late String functionName;
    late Map<String, dynamic> parameters;
    final commands = SupabaseMapCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        parameters = params;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'version': 4,
            'place': {...params['p_place'], 'id': 12},
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

    final result = await commands.savePlace(
        7,
        PlaceModel(
          id: 12,
          aggregateVersion: 3,
          title: 'Stage',
          latLng: {'lat': 49.1, 'lng': 18.2},
          isHidden: false,
        ));

    expect(functionName, 'save_place_client_sync_v1');
    expect(parameters['p_expected_version'], 3);
    expect(parameters['p_command_id'], isA<String>());
    expect((parameters['p_place'] as Map)['title'], 'Stage');
    expect(result.entity?.aggregateVersion, 4);
  });

  test('path and place-type commands serialize closed DTOs', () async {
    final calls = <String, Map<String, dynamic>>{};
    final commands = SupabaseMapCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        calls[name] = params;
        final isPath = name == 'save_path_client_sync_v1';
        return {
          'status': 'unchanged',
          'code': 200,
          'data': {
            'version': 2,
            if (isPath) 'path': {...params['p_path'], 'id': 5},
            if (!isPath) 'placeType': {...params['p_place_type'], 'id': 6},
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

    await commands.savePath(
        7,
        PathGroupsModel(
          id: 5,
          aggregateVersion: 2,
          title: 'Route',
          pathData: [
            [PathNode.place(12)]
          ],
          isHidden: false,
        ));
    await commands.savePlaceType(
        7,
        PlaceTypeModel(
          id: 6,
          aggregateVersion: 2,
          occasion: 7,
          code: 'stage',
          title: 'Stage',
        ));

    expect((calls['save_path_client_sync_v1']!['p_path'] as Map).keys,
        containsAll(<String>['id', 'title', 'pathData', 'isHidden']));
    expect(
        (calls['save_place_type_client_sync_v1']!['p_place_type'] as Map).keys,
        containsAll(<String>['id', 'code', 'title', 'isHidden', 'isDefault']));
  });

  test('icon creation is bound to the immutable icon command', () async {
    late String functionName;
    final commands = SupabaseIconCommands.withTransport(ClientCommandTransport(
      (name, params) async {
        functionName = name;
        return {
          'status': 'applied',
          'code': 200,
          'data': {
            'icon': {
              'id': 9,
              'link': (params['p_icon'] as Map)['link'],
              'data': (params['p_icon'] as Map)['svg'],
              'unit': 2,
              'organization': 1,
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

    final result = await commands.create(
      occasionId: 7,
      link: 'tent',
      svg: '<svg/>',
    );
    expect(functionName, 'save_icon_client_sync_v1');
    expect(result.icon?.id, 9);
  });
}

class _MapCommandsStub implements MapCommands {
  _MapCommandsStub(this.status);

  final MapCommandStatus status;

  @override
  Future<MapCommandResult<PlaceModel>> deletePlace(
          int occasionId, PlaceModel place) async =>
      MapCommandResult(status: status, version: place.aggregateVersion);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
