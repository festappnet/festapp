import 'package:fstapp/components/icons/place_type_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/data_services/client_sync/client_command_transport.dart';
import 'package:fstapp/data_services/client_sync/client_command_response.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';

enum MapCommandStatus { applied, unchanged, rejected, conflict }

class MapCommandResult<T> {
  const MapCommandResult({
    required this.status,
    required this.version,
    this.entity,
  });

  final MapCommandStatus status;
  final int version;
  final T? entity;
}

abstract interface class MapCommands {
  Future<MapCommandResult<PlaceModel>> savePlace(
      int occasionId, PlaceModel place);
  Future<MapCommandResult<PlaceModel>> deletePlace(
      int occasionId, PlaceModel place);
  Future<MapCommandResult<PlaceModel>> movePlace(
      int occasionId, PlaceModel place, double lat, double lng);
  Future<MapCommandResult<PlaceTypeModel>> savePlaceType(
      int occasionId, PlaceTypeModel placeType);
  Future<MapCommandResult<PlaceTypeModel>> deletePlaceType(
      int occasionId, PlaceTypeModel placeType);
  Future<MapCommandResult<PathGroupsModel>> savePath(
      int occasionId, PathGroupsModel path);
  Future<MapCommandResult<PathGroupsModel>> deletePath(
      int occasionId, PathGroupsModel path);
}

/// Statically binds map editing intents to their canonical v1 RPCs.
class SupabaseMapCommands implements MapCommands {
  SupabaseMapCommands(SupabaseClient client)
      : _transport = ClientCommandTransport.supabase(client),
        _actorId = (() => client.auth.currentUser?.id);

  SupabaseMapCommands.withTransport(this._transport) : _actorId = (() => null);

  final ClientCommandTransport _transport;
  final String? Function() _actorId;

  @override
  Future<MapCommandResult<PlaceModel>> savePlace(
      int occasionId, PlaceModel place) async {
    final raw = await _transport.invoke('save_place_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': place.id == null ? null : place.aggregateVersion,
      'p_place': {
        if (place.id case final id?) 'id': id,
        'title': place.title,
        'description': place.description,
        'type': place.type,
        'coordinates': {PlaceModel.coordinatesLatLngKey: place.latLng},
        'isHidden': place.isHidden,
        'order': place.order,
        'icon': place.icon,
      },
    });
    return _decode(raw, 'place', PlaceModel.fromJson);
  }

  @override
  Future<MapCommandResult<PlaceModel>> deletePlace(
      int occasionId, PlaceModel place) async {
    final id = place.id;
    if (id == null) throw ArgumentError('Deleting a place requires its ID');
    final raw = await _transport.invoke('delete_place_client_sync_v1', {
      'p_occasion': occasionId,
      'p_place_id': id,
      'p_expected_version': place.aggregateVersion,
    });
    return _decode(raw, 'place', PlaceModel.fromJson);
  }

  @override
  Future<MapCommandResult<PlaceModel>> movePlace(
      int occasionId, PlaceModel place, double lat, double lng) async {
    final id = place.id;
    if (id == null) throw ArgumentError('Moving a place requires its ID');
    final context = ClientSyncRuntime.mutationContextToken;
    final actor = _actorId();
    final raw = await _transport.invokeIntent(
        '$actor:$occasionId:map.move', 'move_place_client_sync_v1', {
      'p_occasion': occasionId,
      'p_place_id': id,
      'p_expected_version': place.aggregateVersion,
      'p_lat': lat,
      'p_lng': lng,
    });
    return _decode(raw, 'place', PlaceModel.fromJson,
        expectedContextToken: context, activate: actor == _actorId());
  }

  @override
  Future<MapCommandResult<PlaceTypeModel>> savePlaceType(
      int occasionId, PlaceTypeModel placeType) async {
    final raw = await _transport.invoke('save_place_type_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version':
          placeType.id == null ? null : placeType.aggregateVersion,
      'p_place_type': {
        if (placeType.id case final id?) 'id': id,
        'code': placeType.code,
        'title': placeType.title,
        'icon': placeType.icon,
        'order': placeType.order,
        'isHidden': placeType.isHidden ?? false,
        'isDefault': placeType.isDefault ?? false,
      },
    });
    return _decode(raw, 'placeType', PlaceTypeModel.fromJson);
  }

  @override
  Future<MapCommandResult<PlaceTypeModel>> deletePlaceType(
      int occasionId, PlaceTypeModel placeType) async {
    final id = placeType.id;
    if (id == null) {
      throw ArgumentError('Deleting a place type requires its ID');
    }
    final raw = await _transport.invoke('delete_place_type_client_sync_v1', {
      'p_occasion': occasionId,
      'p_place_type_id': id,
      'p_expected_version': placeType.aggregateVersion,
    });
    return _decode(raw, 'placeType', PlaceTypeModel.fromJson);
  }

  @override
  Future<MapCommandResult<PathGroupsModel>> savePath(
      int occasionId, PathGroupsModel path) async {
    final raw = await _transport.invoke('save_path_client_sync_v1', {
      'p_occasion': occasionId,
      'p_expected_version': path.id == null ? null : path.aggregateVersion,
      'p_path': {
        if (path.id case final id?) 'id': id,
        'title': path.title,
        'pathData': path.pathData
                ?.map(
                    (segment) => segment.map((node) => node.toJson()).toList())
                .toList() ??
            const [],
        'data': path.data,
        'icon': path.icon,
        'isHidden': path.isHidden ?? false,
        'order': path.order,
      },
    });
    return _decode(raw, 'path', PathGroupsModel.fromJson);
  }

  @override
  Future<MapCommandResult<PathGroupsModel>> deletePath(
      int occasionId, PathGroupsModel path) async {
    final id = path.id;
    if (id == null) throw ArgumentError('Deleting a path requires its ID');
    final raw = await _transport.invoke('delete_path_client_sync_v1', {
      'p_occasion': occasionId,
      'p_path_id': id,
      'p_expected_version': path.aggregateVersion,
    });
    return _decode(raw, 'path', PathGroupsModel.fromJson);
  }

  Future<MapCommandResult<T>> _decode<T>(Object? raw, String entityKey,
      T Function(Map<String, dynamic>) decodeEntity,
      {String? expectedContextToken, bool activate = true}) async {
    final response = ClientCommandResponse.from(raw);
    if (activate) {
      await response.applyConfirmedReplacements(
          expectedContextToken: expectedContextToken);
    }
    final data = response.data;
    final version = (data['version'] as num?)?.toInt() ?? 0;
    final entityJson = data[entityKey];
    final entity = entityJson is Map
        ? decodeEntity({
            ...entityJson.cast<String, dynamic>(),
            'aggregate_version': version,
          })
        : null;
    return MapCommandResult(
      status: MapCommandStatus.values.byName(response.status),
      version: version,
      entity: entity,
    );
  }
}
