import 'package:fstapp/data_services/client_sync/client_command_identity.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:trina_grid/trina_grid.dart';
import '../map/place_model.dart';
import 'group_participant_model.dart';

class UserGroupInfoModel extends ITrinaRowModel {
  static const String aggregateVersionColumn = TrinaRowVersion.column;
  Map<int, String> checkpointTitlesDict = {};

  static const String progressColumn = "progress";
  static const String participantsColumn = "participants";
  static const String participantsManagementColumn = "participantsManagement";
  static const String isAdminColumn = "is_admin";
  static const String modelReference = "modelReference";

  /// Grid cells store the complete place object so saving can retain both the
  /// selected ID and the immediately renderable title. A text column rejects
  /// that object before Trina can mark the row as changed.
  static TrinaColumnType placeColumnType() => TrinaColumnType.custom(
        defaultValue: null,
        isValid: (value) => value == null || value is PlaceModel,
        compare: (a, b) {
          final aTitle = a is PlaceModel ? a.title ?? '' : '';
          final bTitle = b is PlaceModel ? b.title ?? '' : '';
          return aTitle.compareTo(bTitle);
        },
        toDisplayString: (value) =>
            value is PlaceModel ? value.toBasicString() : '',
      );

  @override
  int? id;
  String title;
  PlaceModel? place;
  int? placeId;
  String? description;
  String? type;
  Map<String, dynamic>? data;
  Set<GroupParticipantModel>? participants = {};
  bool? isAdmin;
  int? persistedPlaceId;
  bool persistedPlaceWasPrivate;
  bool shouldSavePlace = false;
  int aggregateVersion;

  UserGroupInfoModel({
    required this.id,
    required this.title,
    this.description,
    this.type,
    this.data,
    this.place,
    this.placeId,
    this.participants,
    this.isAdmin,
    this.persistedPlaceId,
    this.persistedPlaceWasPrivate = false,
    this.aggregateVersion = 0,
  });

  factory UserGroupInfoModel.fromJson(Map<String, dynamic> json) {
    final place = json[Tb.places.table] != null
        ? PlaceModel.fromJson(json[Tb.places.table])
        : (json[PlaceModel.placeObjectColumn] ?? json['placeData']) != null
            ? PlaceModel.fromJson(
                json[PlaceModel.placeObjectColumn] ?? json['placeData'])
            : null;
    return UserGroupInfoModel(
      id: json[Tb.user_group_info.id],
      title: json[Tb.user_group_info.title],
      type: json[Tb.user_group_info.type],
      data: json[Tb.user_group_info.data],
      placeId: json[Tb.user_group_info.place],
      place: place,
      persistedPlaceId: json[Tb.user_group_info.place] ?? place?.id,
      persistedPlaceWasPrivate: place?.isPrivateGroupLocation ?? false,
      description: json[Tb.user_group_info.description],
      participants: json.containsKey(Tb.user_groups.table)
          ? Set<GroupParticipantModel>.from(json[Tb.user_groups.table]
              .map((e) => GroupParticipantModel.fromJson(e)))
          : json[participantsColumn] != null
              ? Set<GroupParticipantModel>.from(json[participantsColumn]
                  .map((p) => GroupParticipantModel.fromJson(p)))
              : null,
      isAdmin: json[isAdminColumn],
      aggregateVersion: TrinaRowVersion.read(json),
    );
  }

  static UserGroupInfoModel fromPlutoJson(Map<String, dynamic> json) {
    // The reference model is the source of truth for complex data like participants.
    final model = json[modelReference] as UserGroupInfoModel;

    // Update the model with values from directly editable cells.
    model.title = json[Tb.user_group_info.title];
    model.description =
        DataGridHelper.getValueOrNull(json[Tb.user_group_info.description]);
    model.place = json[Tb.user_group_info.place] as PlaceModel?;
    model.aggregateVersion = TrinaRowVersion.read(json);
    return model;
  }

  static UserGroupInfoModel fromGamePlutoJson(Map<String, dynamic> json) {
    return UserGroupInfoModel(
        id: json[Tb.user_group_info.id],
        aggregateVersion: TrinaRowVersion.read(json),
        title: json[Tb.user_group_info.title],
        description: json[Tb.user_group_info.description],
        type: InformationModel.gameType,
        participants: json[participantsColumn] is Set<GroupParticipantModel>
            ? json[participantsColumn]
            : {},
        place: (json[Tb.user_group_info.place] as PlaceModel?),
        isAdmin: json[isAdminColumn]);
  }

  @override
  TrinaRow toTrinaRow(BuildContext context) {
    var checkpoints = (data?["game"] ?? [])
        .where((item) => checkpointTitlesDict.containsKey(item["check_point"]))
        .map((item) => checkpointTitlesDict[item["check_point"]])
        .toList();
    checkpoints.sort();
    var progressText = "${checkpoints.length} [${checkpoints.join(",")}]";

    return TrinaRow(cells: {
      aggregateVersionColumn: TrinaRowVersion.cell(aggregateVersion),
      Tb.user_group_info.id: TrinaCell(value: id),
      Tb.user_group_info.title: TrinaCell(value: title),
      Tb.user_group_info.description: TrinaCell(value: description),
      Tb.user_group_info.place: TrinaCell(value: place),
      Tb.user_group_info.type: TrinaCell(value: type ?? ""),
      progressColumn: TrinaCell(value: progressText),
      isAdminColumn: TrinaCell(value: isAdmin),
      participantsManagementColumn:
          TrinaCell(value: getParticipantsDisplayValue()),
      modelReference: TrinaCell(value: this),
    });
  }

  String getParticipantsDisplayValue() {
    if (participants == null || participants!.isEmpty) {
      return GroupsStrings.noOneAssigned;
    }
    final leader = participants!.firstWhereOrNull((p) => p.isAdmin == true);
    final members = participants!.where((p) => p.isAdmin != true);

    final parts = <String>[];
    if (leader != null) {
      parts.add("⭐ ${leader.userInfo!.toFullNameString()}");
    }
    if (members.isNotEmpty) {
      parts.add(members.map((p) => p.userInfo!.toFullNameString()).join(', '));
    }
    return parts.join(' | ');
  }

  /// Adopt a confirmed write's identity without replacing newer editor fields.
  void acceptSavedIdentity(
      UserGroupInfoModel saved, PlaceModel? submittedPlace) {
    id = saved.id;
    aggregateVersion = saved.aggregateVersion;
    persistedPlaceId = saved.placeId ?? saved.place?.id;
    persistedPlaceWasPrivate = saved.place?.isPrivateGroupLocation ?? false;
    if (identical(place, submittedPlace) &&
        submittedPlace?.isPrivateGroupLocation == true &&
        saved.place?.isPrivateGroupLocation == true &&
        (submittedPlace!.id == null || submittedPlace.id == saved.place!.id)) {
      submittedPlace.id = saved.place!.id;
      submittedPlace.aggregateVersion = saved.place!.aggregateVersion;
    }
    placeId = place?.id;
  }

  String editorIntentFingerprint() {
    final fields = toJson()
      ..remove('id')
      ..remove(aggregateVersionColumn);
    if (place != null) fields.remove('place');
    final placeFields = fields[PlaceModel.placeObjectColumn];
    if (placeFields is Map) {
      placeFields.remove('id');
      placeFields.remove(PlaceModel.aggregateVersionColumn);
    }
    return ClientCommandIdentity.fingerprint(fields);
  }

  void acceptSaved(UserGroupInfoModel saved) {
    id = saved.id;
    title = saved.title;
    description = saved.description;
    type = saved.type;
    data = saved.data;
    place = saved.place;
    placeId = saved.placeId ?? saved.place?.id;
    participants = saved.participants;
    isAdmin = saved.isAdmin;
    aggregateVersion = saved.aggregateVersion;
    persistedPlaceId = placeId;
    persistedPlaceWasPrivate = place?.isPrivateGroupLocation ?? false;
    shouldSavePlace = false;
  }

  void setPlaceForEditing(PlaceModel? value, {bool savePlace = false}) {
    place = value;
    shouldSavePlace = savePlace;
  }

  Map<String, dynamic> toJson() {
    // The backend expects an integer ID. UUIDs are for client-side identification of new rows.
    return {
      Tb.user_group_info.id: id,
      Tb.user_group_info.title: title,
      PlaceModel.placeObjectColumn: place?.toJson(),
      Tb.user_group_info.description: description,
      Tb.user_group_info.type: type,
      Tb.user_group_info.data: data,
      "participants": participants
          ?.map((p) => {
                "user_id": p.userInfo?.id,
                "is_admin": p.isAdmin ?? false,
                // Full user info so the offline cache round-trip keeps the
                // member names (this json is only consumed by the offline
                // cache — DbGroups builds its own payloads for backend
                // writes; GroupParticipantModel.fromJson reads this key).
                Tb.user_info.table: p.userInfo?.toJson(),
              })
          .toList(),
    };
  }

  @override
  Future<void> deleteMethod(BuildContext context) async {
    await DbGroups.deleteUserGroupInfo(this);
  }

  @override
  Future<void> updateMethod(BuildContext context) async {
    await DbGroups.updateUserGroupInfo(this);
  }

  @override
  String toBasicString() => title;
}
