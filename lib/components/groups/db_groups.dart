import 'package:collection/collection.dart';
import 'package:fstapp/components/groups/group_commands.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/map/place_model.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/data_services/client_sync/client_sync_runtime.dart';
import 'package:fstapp/data_services/client_sync/client_sync_projection.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DbGroups {
  static final _supabase = Supabase.instance.client;
  static final GroupCommands _commands = SupabaseGroupCommands(_supabase);
  static const editorGroupsKey = 'groups';
  static const editorGameDefinitionsKey = 'game_definitions';
  static const editorPlacesKey = 'places';

  static Future<List<UserGroupInfoModel>> getGroupsWithPlaces() async {
    return (await getUserGroupsEditorData()).groups;
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

  static Future<UserGroupInfoModel> getUserGroupForEdit(int id) async {
    final raw = await _supabase.rpc('get_user_group_editor_bundle_v1', params: {
      'p_occasion': RightsService.currentOccasionId()!,
      'p_group_id': id,
    });
    if (raw is! Map) throw StateError('Group editor unavailable');
    return UserGroupInfoModel.fromJson(raw.cast<String, dynamic>());
  }

  static Future<void> updateUserGroupInfo(UserGroupInfoModel model) async {
    await saveWithCommands(
        _commands, RightsService.currentOccasionId()!, model);
  }

  static Future<void> saveWithCommands(
      GroupCommands commands, int occasionId, UserGroupInfoModel model) async {
    final context = ClientSyncRuntime.mutationContextToken;
    final actor = RightsService.currentUser()?.id;
    final snapshot = model.editorIntentFingerprint();
    final submittedId = model.id;
    final submittedPlace = model.place;
    final result = await commands.save(occasionId, model);
    if (result.status == GroupCommandStatus.conflict) {
      throw StateError('Group was changed by another editor');
    }
    if (result.status == GroupCommandStatus.rejected || result.group == null) {
      throw StateError('Group save was rejected');
    }
    if (ClientSyncRuntime.isCurrentMutationContext(context) &&
        RightsService.currentUser()?.id == actor &&
        (RightsService.currentOccasionId() == null ||
            RightsService.currentOccasionId() == occasionId) &&
        (model.id == submittedId ||
            (submittedId == null && model.id == result.group!.id)) &&
        result.version >= model.aggregateVersion) {
      final saved = result.group!;
      if (identical(model.place, submittedPlace) &&
          model.editorIntentFingerprint() == snapshot) {
        model.acceptSaved(saved);
      } else {
        model.acceptSavedIdentity(saved, submittedPlace);
      }
    }
  }

  /// Atomically makes the CSV group column authoritative for imported users.
  /// The RPC replaces standard-group membership and leaves typed groups alone.
  static Future<void> replaceImportedUserGroups(
      Map<String, String?> groupTitleByUserId) async {
    if (!RightsService.isEditor()) {
      throw Exception("Must be editor to import groups.");
    }

    final result = await _commands.replaceAssignments(
        RightsService.currentOccasionId()!, groupTitleByUserId);
    if (result.status == GroupCommandStatus.rejected ||
        result.status == GroupCommandStatus.conflict) {
      throw StateError('Group assignment import was rejected or conflicted');
    }
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
