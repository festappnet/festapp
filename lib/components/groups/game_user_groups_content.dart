import 'package:collection/collection.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/information/information_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/users/db_users.dart';

import 'group_strings.dart';
import 'participants_management_dialog.dart';
import 'package:trina_grid/trina_grid.dart';

class GameUserGroupsContent extends StatefulWidget {
  const GameUserGroupsContent({super.key});

  @override
  _GameUserGroupsContentState createState() => _GameUserGroupsContentState();
}

class _GameUserGroupsContentState extends State<GameUserGroupsContent> {
  // Changed to Map to match the logic in UserGroupsTab for efficient lookup
  Map<String, UserInfoModel> _allUsersMap = {};
  SingleDataGridController<UserGroupInfoModel>? controller;

  @override
  void initState() {
    super.initState();
    _loadAllUsers();
  }

  Future<void> _loadAllUsers() async {
    // Loading basics and converting to Map<ID, User> to support the dialog logic
    var usersList = await DbUsers.getAllUsersBasics();
    if (mounted) {
      setState(() {
        _allUsersMap = {
          for (var u in usersList)
            if (u.id != null) u.id!: u
        };
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Controller initialization moved here to match the structure of UserGroupsTab
    controller ??= SingleDataGridController<UserGroupInfoModel>(
      context: context,
      loadData: () => DbGroups.getAllUserGroupInfo(InformationModel.gameType),
      fromPlutoJson: UserGroupInfoModel.fromGamePlutoJson,
      firstColumnType: DataGridFirstColumn.delete,
      idColumn: Tb.user_group_info.id,
      getNewObject: () => UserGroupInfoModel(
        id: null,
        title: GroupsStrings.newGroup,
        participants: {},
      ),
      columns: [
        // Hidden column to access the full model in renderers
        TrinaColumn(
          title: "",
          hide: true,
          field: UserGroupInfoModel.modelReference,
          type: TrinaColumnType.text(),
        ),
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: Tb.user_group_info.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          enableEditingMode: false,
          width: 50,
          renderer: (rendererContext) =>
              DataGridHelper.idRenderer(rendererContext),
        ),
        TrinaColumn(
          title: CommonStrings.name,
          field: Tb.user_group_info.title,
          type: TrinaColumnType.text(),
          width: 200,
        ),
        TrinaColumn(
          title: CommonStrings.progress,
          field: UserGroupInfoModel.progressColumn,
          readOnly: true,
          type: TrinaColumnType.text(),
          width: 200,
        ),
        TrinaColumn(
          title: CommonStrings.participants,
          // Using the standard participants column field, but the logic now uses the modelReference
          field: UserGroupInfoModel.participantsManagementColumn,
          type: TrinaColumnType.text(defaultValue: <UserInfoModel>{}),
          enableEditingMode: false,
          width: 600,
          renderer: (rendererContext) {
            // 1. Retrieve the full model
            final model = rendererContext
                .row
                .cells[UserGroupInfoModel.modelReference]!
                .value as UserGroupInfoModel;

            // 2. Extract participants logic (Leader vs Members)
            // Note: If 'participants' is null in the game model, fallback to empty list
            final participants = model.participants ?? {};
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
                      // Ensure user data is fully populated from the map
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

                      // Calculate all currently assigned users to prevent duplicates (if needed by dialog)
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

                      // Open the management dialog
                      await showDialog(
                          context: context,
                          builder: (_) => ParticipantsManagementDialog(
                                group: model,
                                allUsers: _allUsersMap.values.toList(),
                                allAssignedUserIds: allAssignedUserIds,
                              ));

                      // Update the cell value if data changed
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
                          .withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          // Leader Chip
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
                          // Member Chips
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
