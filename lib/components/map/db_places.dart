import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/map/icon_model.dart';
import 'package:fstapp/components/map/path_group_model.dart';
import 'package:fstapp/components/map/map_commands.dart';
import 'package:fstapp/components/map/map_place_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'place_model.dart';

class DbPlaces {
  static final _supabase = Supabase.instance.client;
  static final MapCommands _commands = SupabaseMapCommands(_supabase);

  static Future<List<PlaceModel>> getMapPlaces() async {
    var data = await _supabase
        .from(Tb.places.table)
        .select()
        .eq(Tb.places.is_hidden, false)
        .eq(Tb.places.occasion, RightsService.currentOccasionId()!);
    var toReturn =
        List<PlaceModel>.from(data.map((x) => PlaceModel.fromJson(x)));
    toReturn.sortPlaces();
    return toReturn;
  }

  static Future<List<PlaceModel>> getAllPlaces() async {
    if (RightsService.isEditor() || RightsService.isEditorView()) {
      return getAllPlacesForEditor();
    }
    var data = await _supabase
        .from(Tb.places.table)
        .select()
        .eq(Tb.places.occasion, RightsService.currentOccasionId()!);
    var toReturn =
        List<PlaceModel>.from(data.map((x) => PlaceModel.fromJson(x)));
    toReturn.sortPlaces();
    return toReturn;
  }

  /// Loads the versioned place rows required by the editor grid.
  static Future<List<PlaceModel>> getAllPlacesForEditor() async {
    final response = await _supabase.rpc('get_map_editor_bundle_v1', params: {
      'p_occasion': RightsService.currentOccasionId()!,
    });
    return decodeMapEditorPlacesResponse(response);
  }

  static List<PlaceModel> decodeMapEditorPlacesResponse(Object? response) {
    final data = (response as Map).cast<String, dynamic>();
    if (data['code'] != 200) {
      throw StateError('Map editor places could not be loaded');
    }
    final places = ((data['places'] as List?) ?? const [])
        .map((x) => PlaceModel.fromJson((x as Map).cast<String, dynamic>()))
        .toList();
    places.sortPlaces();
    return places;
  }

  static Future<List<PlaceModel>> getPlacesIn(List<int> ids) async {
    var data = await _supabase
        .from(Tb.places.table)
        .select()
        .inFilter(Tb.places.id, ids);
    var toReturn =
        List<PlaceModel>.from(data.map((x) => PlaceModel.fromJson(x)));
    toReturn.sortPlaces();
    return toReturn;
  }

  static Future<List<IconModel>> getAllIcons() async {
    var data = await _supabase
        .from(Tb.icons.table)
        .select()
        .eq(Tb.icons.organization, AppConfig.organization);
    return List<IconModel>.from(data.map((x) => IconModel.fromJson(x)));
  }

  static Future<PlaceModel> getPlace(int id) async {
    var data = await _supabase
        .from(Tb.places.table)
        .select()
        .eq(Tb.places.id, id)
        .single();
    return PlaceModel.fromJson(data);
  }

  static Future<void> deletePlace(PlaceModel placeModel) async {
    await deletePlaceWithCommands(
      commands: _commands,
      occasionId: RightsService.currentOccasionId()!,
      place: placeModel,
    );
  }

  /// The only supported place-deletion boundary.
  ///
  /// This remains independent of the selected read projection: stale or legacy
  /// contexts must not fall back to direct table DML because that bypasses the
  /// map commit/publication contract and may lack table privileges entirely.
  static Future<void> deletePlaceWithCommands({
    required MapCommands commands,
    required int occasionId,
    required PlaceModel place,
  }) async {
    final result = await commands.deletePlace(occasionId, place);
    if (result.status == MapCommandStatus.conflict) {
      throw StateError('Place was changed by another editor');
    }
    if (result.status == MapCommandStatus.rejected) {
      throw StateError('Place delete was rejected');
    }
  }

  static Future<PlaceModel> updatePlace(PlaceModel placeModel) async {
    return updatePlaceWithCommands(
      commands: _commands,
      occasionId: RightsService.currentOccasionId()!,
      place: placeModel,
    );
  }

  static Future<PlaceModel> updatePlaceWithCommands({
    required MapCommands commands,
    required int occasionId,
    required PlaceModel place,
  }) async {
    final result = await commands.savePlace(occasionId, place);
    if (result.status == MapCommandStatus.conflict) {
      throw StateError('Place was changed by another editor');
    }
    if (result.status == MapCommandStatus.rejected || result.entity == null) {
      throw StateError('Place save was rejected');
    }
    return result.entity!;
  }

  static Future<void> saveLocation(
      MapPlaceModel place, double lat, double lng) async {
    // Fast UX guard mirroring the RPC's permission check (editor OR group admin
    // of this place). The canonical move command is the source of truth — a
    // group admin who isn't an editor cannot move a place via a direct RLS
    // UPDATE (it silently touches 0 rows), so the write must go through it.
    if (!(RightsService.isEditor() ||
        (RightsService.isGroupAdmin() &&
            RightsService.currentUserGroup()!.place!.id == place.id))) {
      throw Exception("You cannot change this place.");
    }
    final result = await _commands.movePlace(
        RightsService.currentOccasionId()!,
        PlaceModel(id: place.id, aggregateVersion: place.aggregateVersion),
        lat,
        lng);
    if (result.status == MapCommandStatus.conflict) {
      throw StateError('Place was changed by another editor');
    }
    if (result.status == MapCommandStatus.rejected || result.entity == null) {
      throw StateError('Place move was rejected');
    }
    if (result.version >= place.aggregateVersion)
      place.aggregateVersion = result.version;
  }

  /// Fetch all path-groups, including their `List<List<int>>` `path_data`.
  static Future<List<PathGroupsModel>> getAllPathGroups() async {
    if (ClientSyncRuntime.isV1Selected) {
      final response = await _supabase.rpc('get_map_editor_bundle_v1', params: {
        'p_occasion': RightsService.currentOccasionId()!,
      });
      final data = (response as Map).cast<String, dynamic>();
      final paths = ((data['paths'] as List?) ?? const [])
          .map((x) =>
              PathGroupsModel.fromJson((x as Map).cast<String, dynamic>()))
          .toList();
      paths.sortPathGroups();
      return paths;
    }
    final data = await _supabase
        .from(Tb.path_groups.table)
        .select('${Tb.path_groups.id},'
            '${Tb.path_groups.title},'
            '${Tb.path_groups.order},'
            '${Tb.path_groups.is_hidden},'
            '${Tb.path_groups.data},'
            '${Tb.path_groups.path_data},'
            '${Tb.path_groups.icon}')
        .eq(Tb.path_groups.occasion, RightsService.currentOccasionId()!);

    var toReturn = (data as List<dynamic>)
        .map((x) => PathGroupsModel.fromJson(x as Map<String, dynamic>))
        .toList();
    toReturn.sortPathGroups();
    return toReturn;
  }

  /// Insert or update a path‑group, writing its `pathData` directly into
  /// the `path_data` JSON column.
  static Future<void> updatePathGroup(PathGroupsModel model) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result =
          await _commands.savePath(RightsService.currentOccasionId()!, model);
      if (result.status == MapCommandStatus.conflict) {
        throw StateError('Path was changed by another editor');
      }
      if (result.status == MapCommandStatus.rejected || result.entity == null) {
        throw StateError('Path save was rejected');
      }
      final updated = result.entity!;
      model
        ..id = updated.id
        ..data = updated.data
        ..pathData = updated.pathData
        ..aggregateVersion = updated.aggregateVersion;
      return;
    }
    // build our upsert object
    final upsertObj = <String, dynamic>{
      Tb.path_groups.title: model.title,
      Tb.path_groups.order: model.order,
      Tb.path_groups.data: model.data,
      Tb.path_groups.is_hidden: model.isHidden,
      Tb.path_groups.path_data: model.pathData
          ?.map((seg) => seg.map((n) => n.toJson()).toList())
          .toList(),
      Tb.path_groups.icon: model.icon,
    };

    dynamic pgData;
    if (model.id != null) {
      // --- UPDATE existing
      upsertObj[Tb.path_groups.id] = model.id;
      pgData = await _supabase
          .from(Tb.path_groups.table)
          .update(upsertObj)
          .eq(Tb.path_groups.id, model.id!)
          .select()
          .single();
    } else {
      // --- INSERT new
      upsertObj[Tb.path_groups.occasion] = RightsService.currentOccasionId()!;
      pgData = await _supabase
          .from(Tb.path_groups.table)
          .insert(upsertObj)
          .select()
          .single();
    }

    // refresh local model if needed
    final updated = PathGroupsModel.fromJson(pgData as Map<String, dynamic>);
    model.id = updated.id;
    model.data = updated.data;
    model.pathData = updated.pathData;
    // (and any other fields you want to keep in sync)
  }

  /// Delete a path‑group (now only needs to remove the row itself)
  static Future<void> deletePathGroup(PathGroupsModel model) async {
    if (ClientSyncRuntime.isV1Selected) {
      final result =
          await _commands.deletePath(RightsService.currentOccasionId()!, model);
      if (result.status == MapCommandStatus.conflict) {
        throw StateError('Path was changed by another editor');
      }
      if (result.status == MapCommandStatus.rejected) {
        throw StateError('Path delete was rejected');
      }
      return;
    }
    await _supabase
        .from(Tb.path_groups.table)
        .delete()
        .eq(Tb.path_groups.id, model.id!);
  }
}
