import 'package:collection/collection.dart';
import 'package:fstapp/components/groups/group_commands.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:festapp_core/map.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbGroups {
  static final _supabase = Supabase.instance.client;
  static GroupCommands get _commands => SupabaseGroupCommands(_supabase);
  static const editorGroupsKey = 'groups';
  static const editorGameDefinitionsKey = 'game_definitions';
  static const editorPlacesKey = 'places';

  static Future<List<UserGroupInfoModel>> getGroupsWithPlaces() async {
    final data = await _supabase.rpc('get_group_places_for_map_v1', params: {
      'p_occasion': RightsService.currentOccasionId()!,
    }) as List;
    return List<UserGroupInfoModel>.from(
        data.map((x) => UserGroupInfoModel.fromJson(x)));
  }

  static Future<UserGroupsEditorData> getUserGroupsEditorData(
      [String? type]) async {
    final response = await _supabase.rpc(
      'get_user_groups_editor_bundle_v1',
      params: {
        'p_occasion': RightsService.currentOccasionId()!,
        'p_type': type,
      },
    );

    return parseUserGroupsEditorData(response, type);
  }

  static UserGroupsEditorData parseUserGroupsEditorData(dynamic response,
      [String? type]) {
    final List<dynamic> groupData = response[editorGroupsKey];
    final Map<String, dynamic>? gameDefsData =
        response[editorGameDefinitionsKey];

    var toReturn = List<UserGroupInfoModel>.from(
        groupData.map((x) => UserGroupInfoModel.fromJson(x)));

    if (type == InformationModel.gameType && gameDefsData != null) {
      Map<int, String> dict = gameDefsData
          .map((key, value) => MapEntry(int.parse(key), value as String));

      for (var u in toReturn) {
        u.checkpointTitlesDict = dict;
      }
    }

    toReturn.sort((a, b) {
      return Utilities.naturalCompare(a.title, b.title);
    });

    final places = List<PlaceModel>.from(
      (response[editorPlacesKey] ?? const [])
          .map((x) => PlaceModel.fromJson(x)),
    );
    places.sort((a, b) =>
        (a.title ?? '').toLowerCase().compareTo((b.title ?? '').toLowerCase()));

    return UserGroupsEditorData(groups: toReturn, places: places);
  }

  static Future<List<UserGroupInfoModel>> getAllUserGroupInfo(
          [String? type]) async =>
      (await getUserGroupsEditorData(type)).groups;

  static Future<UserGroupInfoModel?> getUserGroupInfo(int id) async {
    final response = await _supabase.rpc(
      'get_user_group_info_with_users',
      params: {
        'p_group_id': id,
      },
    );

    return UserGroupInfoModel.fromJson(response);
  }

  /// Canonical payload for persisting the editable group fields.
  ///
  /// A custom place must be saved before this is called so its generated ID
  /// can cross the persistence boundary just like an existing catalog place.
  static Map<String, dynamic> buildUserGroupUpsert(
    UserGroupInfoModel model,
  ) {
    return {
      Tb.user_group_info.title: model.title,
      if (model.type != null) Tb.user_group_info.type: model.type,
      if (model.description != null)
        Tb.user_group_info.description: model.description,
      Tb.user_group_info.place: model.place?.id,
    };
  }

  static Future<void> updateUserGroupInfo(UserGroupInfoModel model) async {
    if (!(RightsService.isEditor() || (model.isAdmin ?? false))) {
      throw Exception("Must be leader or admin to change the group.");
    }

    final result =
        await _commands.save(RightsService.currentOccasionId()!, model);
    if (result.status == GroupCommandStatus.conflict) {
      throw StateError('Group was changed by another editor');
    }
    if (result.status == GroupCommandStatus.rejected || result.group == null) {
      throw StateError('Group save was rejected');
    }
    model
      ..id = result.group!.id
      ..place = result.group!.place
      ..aggregateVersion = result.version
      ..persistedPlaceId = result.group!.place?.id
      ..persistedPlaceWasPrivate =
          result.group!.place?.isPrivateGroupLocation ?? false
      ..shouldSavePlace = false;
    return;
  }

  static Future<void> addMembers(
      UserGroupInfoModel group, List<String> userIds) async {
    final result = await _commands.addMembers(
        RightsService.currentOccasionId()!, group.id!, userIds);
    if (result.status == GroupCommandStatus.rejected ||
        result.status == GroupCommandStatus.conflict) {
      throw StateError('Adding group members was rejected');
    }
    group.aggregateVersion = result.version;
  }

  static Future<void> deleteUserGroupInfo(UserGroupInfoModel model) async {
    final result =
        await _commands.delete(RightsService.currentOccasionId()!, model);
    if (result.status == GroupCommandStatus.conflict) {
      throw StateError('Group was changed by another editor');
    }
    if (result.status == GroupCommandStatus.rejected) {
      throw StateError('Group delete was rejected');
    }
    return;
  }

  static Future<List<int>> getCorrectlyGuessedCheckpoints() async {
    if (ClientSyncRuntime.isV1Selected) {
      final groups = await ClientSyncProjection.groups();
      final gameGroup = groups.firstWhereOrNull(
        (group) => group.type == InformationModel.gameType,
      );
      return List<int>.from(
        (gameGroup?.data?['game'] as List? ?? const [])
            .map((entry) => (entry as Map)['check_point'])
            .whereType<num>()
            .map((value) => value.toInt()),
      );
    }
    var response = await _supabase.rpc('game_get_correctly_guessed_checkpoints',
        params: {'oc': RightsService.currentOccasionId()});
    if (response == null || response["code"] != 200) {
      return [];
    }
    List<int> checkPoints =
        List<int>.from(response["data"].map((entry) => entry['check_point']));

    return checkPoints;
  }

  static Future<Set<UserGroupInfoModel>> getUserGroups() async {
    if (ClientSyncRuntime.isV1Selected) {
      return (await ClientSyncProjection.groups()).toSet();
    }
    final response = await _supabase.rpc('get_user_groups',
        params: {'p_occasion_id': RightsService.currentOccasionId()!});
    return Set.from(response.values.map((groupJson) =>
        UserGroupInfoModel.fromJson(groupJson as Map<String, dynamic>)));
  }
}

class UserGroupsEditorData {
  final List<UserGroupInfoModel> groups;
  final List<PlaceModel> places;

  const UserGroupsEditorData({
    required this.groups,
    required this.places,
  });
}
