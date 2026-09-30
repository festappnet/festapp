import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/groups/group_place_dialog.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/map/map_page.dart';
import 'package:trina_grid/trina_grid.dart';

import '../map/place_model.dart';
import 'group_strings.dart';
import 'participants_management_dialog.dart';

class UserGroupsTab extends StatefulWidget {
  const UserGroupsTab({super.key});

  @override
  _UserGroupsTabState createState() => _UserGroupsTabState();
}

class _UserGroupsTabState extends State<UserGroupsTab> {
  Map<String, UserInfoModel> _allUsersMap = {};
  List<PlaceModel> _places = [];
  SingleDataGridController<UserGroupInfoModel>? controller;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<List<UserGroupInfoModel>> _loadGroupsForGrid() async {
    final data = await DbGroups.getUserGroupsEditorData();
    _places = data.places;
    return data.groups;
  }

  Future<void> _chooseGroupPlace(
    TrinaColumnRendererContext rendererContext,
  ) async {
    final row = rendererContext.row;
    final model = row.cells[UserGroupInfoModel.modelReference]!.value
        as UserGroupInfoModel;
    final currentPlace =
        row.cells[Tb.user_group_info.place]?.value as PlaceModel?;
    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => GroupPlaceDialog(
        places: _places,
        currentPlace: currentPlace,
      ),
    );
    if (!mounted || result == null) return;

    var shouldSavePlace = false;
    PlaceModel? selectedPlace;
    if (result is PlaceModel) {
      selectedPlace = result;
    } else if (result is RemoveGroupPlaceAction) {
      selectedPlace = null;
    } else if (result is UseCustomGroupLocationAction) {
      final title = row.cells[Tb.user_group_info.title]?.value as String?;
      final customPlace = currentPlace?.isPrivateGroupLocation == true
          ? currentPlace!
          : PlaceModel(
              title: title,
              description: '',
              type: PlaceModel.groupType,
              isHidden: true,
              latLng: currentPlace?.hasCoordinates == true
                  ? Map<String, dynamic>.from(currentPlace!.latLng as Map)
                  : FeatureService.getDefaultLocation(),
            );
      final coordinates = await RouterService.navigatePageInfo(
        context,
        MapEditorRoute(mode: PlaceMapEditorMode(customPlace)),
      );
      if (!mounted || coordinates == null) return;
      customPlace.latLng = coordinates;
      shouldSavePlace = true;
      selectedPlace = customPlace;
    } else {
      return;
    }

    model.setPlaceForEditing(selectedPlace, savePlace: shouldSavePlace);
    final cell = row.cells[Tb.user_group_info.place]!;
    rendererContext.stateManager.changeCellValue(
      cell,
      selectedPlace,
      force: true,
    );
  }

  Future<void> _loadAllUsers() async {
    var bundle = await DbUsers.getOccasionUsersWithOrdersBundle();
    _allUsersMap = bundle.users;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller ??= SingleDataGridController<UserGroupInfoModel>(
      context: context,
      loadData: _loadGroupsForGrid,
      fromPlutoJson: UserGroupInfoModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.delete,
      idColumn: Tb.user_group_info.id,
      getNewObject: () => UserGroupInfoModel(
        id: null,
        title: GroupsStrings.newGroup,
        participants: {},
      ),
      columns: [
        TrinaColumn(
          title: "",
          hide: true,
          field: UserGroupInfoModel.modelReference,
          type: TrinaColumnType.text(),
        ),
        TrinaColumn(
          hide: true,
          title: GroupsStrings.columnId,
          field: Tb.user_group_info.id,
          type: TrinaColumnType.text(defaultValue: ""),
          readOnly: true,
          enableEditingMode: false,
          width: 50,
          renderer: (rendererContext) =>
              DataGridHelper.idRenderer(rendererContext),
        ),
        TrinaColumn(
          title: GroupsStrings.columnName,
          field: Tb.user_group_info.title,
          type: TrinaColumnType.text(),
          width: 150,
        ),
        TrinaColumn(
          title: GroupsStrings.columnParticipants,
          field: UserGroupInfoModel.participantsManagementColumn,
          type: TrinaColumnType.text(),
          width: 600,
          enableEditingMode: false,
          renderer: (rendererContext) {
            final model = rendererContext
                .row
                .cells[UserGroupInfoModel.modelReference]!
                .value as UserGroupInfoModel;

            final participants = model.participants!;
            final leader =
                participants.firstWhereOrNull((p) => p.isAdmin == true);
            final members = participants.where((p) => p.isAdmin != true);
            final count = participants.length;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.settings),
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: GroupsStrings.manageParticipantsTooltip,
                    onPressed: () async {
                      if (model.participants != null &&
                          _allUsersMap.isNotEmpty) {
                        for (final participant in model.participants!) {
                          if (participant.userInfo?.id != null &&
                              _allUsersMap
                                  .containsKey(participant.userInfo!.id)) {
                            participant.userInfo =
                                _allUsersMap[participant.userInfo!.id];
                          }
                        }
                      }

                      final initialDisplayValue =
                          model.getParticipantsDisplayValue();
                      final allAssignedUserIds = <String>{};
                      for (final row in rendererContext.stateManager.rows) {
                        final rowModel = row
                            .cells[UserGroupInfoModel.modelReference]
                            ?.value as UserGroupInfoModel?;
                        rowModel?.participants?.forEach((p) {
                          if (p.userInfo?.id != null) {
                            allAssignedUserIds.add(p.userInfo!.id!);
                          }
                        });
                      }

                      await showDialog(
                          context: context,
                          builder: (_) => ParticipantsManagementDialog(
                                group: model,
                                allUsers: _allUsersMap.values.toList(),
                                allAssignedUserIds: allAssignedUserIds,
                              ));

                      final newDisplayValue =
                          model.getParticipantsDisplayValue();
                      if (initialDisplayValue != newDisplayValue) {
                        rendererContext.stateManager.changeCellValue(
                            rendererContext.cell, newDisplayValue,
                            force: true);
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  Text(
                    "($count)",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          if (leader != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4.0),
                              child: Chip(
                                avatar: Icon(Icons.star,
                                    color: Colors.amber.shade800, size: 16),
                                label:
                                    Text(leader.userInfo!.toFullNameString()),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                          ...members.map((p) => Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: Chip(
                                  label: Text(p.userInfo!.toFullNameString()),
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                              )),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        TrinaColumn(
          width: 150,
          title: GroupsStrings.columnContent,
          field: Tb.user_group_info.description,
          type: TrinaColumnType.text(defaultValue: null),
          renderer: (rendererContext) {
            return DataGridHelper.buildHtmlEditorButton(context: context,
              field: Tb.user_group_info.description, rendererContext: rendererContext,
              occasionId: RightsService.currentOccasionId(),
              loadContent: () async => rendererContext.row.cells[Tb.user_group_info.description]?.value as String?);

          },
        ),
        TrinaColumn(
          width: 220,
          title: GroupsStrings.columnPlace,
          field: Tb.user_group_info.place,
          type: UserGroupInfoModel.placeColumnType(),
          enableEditingMode: false,
          renderer: (rendererContext) {
            final place = rendererContext
                .row.cells[Tb.user_group_info.place]?.value as PlaceModel?;
            return ElevatedButton(
              onPressed: () => _chooseGroupPlace(rendererContext),
              child: Row(
                children: [
                  Icon(place == null
                      ? Icons.add_location_alt_outlined
                      : Icons.location_pin),
                  Padding(
                    padding: const EdgeInsets.all(6),
                    child: Text(
                      place?.title ?? GroupsStrings.choosePlace,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (controller == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleTableDataGrid<UserGroupInfoModel>(controller!);
  }
}
