import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/users/unit_user_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/views/users_tab_helper.dart';

class UnitUsersScreen extends StatefulWidget {
  final UnitModel unit;

  const UnitUsersScreen({super.key, required this.unit});

  @override
  _UnitUsersScreenState createState() => _UnitUsersScreenState();
}

class _UnitUsersScreenState extends State<UnitUsersScreen> {
  static const List<String> columnIdentifiers = [
    UserColumns.ID,
    UserColumns.UNIT,
    UserColumns.EMAIL,
    UserColumns.NAME,
    UserColumns.SURNAME,
    UserColumns.SEX,
    UserColumns.UNIT_MANAGER,
    UserColumns.UNIT_EDITOR,
    UserColumns.UNIT_EDITOR_VIEW,
  ];

  SingleDataGridController<UnitUserModel>? controller;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    controller = SingleDataGridController<UnitUserModel>(
        context: context,
        loadData: () => DbUsers.getAllUsersFromUnit(widget.unit.id!),
        fromPlutoJson: UnitUserModel.fromPlutoJson,
        firstColumnType: DataGridFirstColumn.deleteAndCheck,
        idColumn: Tb.occasion_users.user,
        actionsExtended: DataGridActionsController(
          areAllActionsEnabled: RightsService.canUpdateUnitUsers,
        ),
        getNewObject: () => UnitUserModel.newRow(widget.unit.id!),
        headerChildren: [
          if (RightsService.isUnitManager())
            DataGridAction(
              name: CommonStrings.addExisting,
              action: (SingleDataGridController p0, [_]) async {
                var users = await DbUsers.getAllUsersFromUnit(widget.unit.id!);
                await UsersTabHelper.addExistingToUnit(
                  context,
                  p0,
                  users,
                  controller!.reloadData,
                  widget.unit.id!,
                );
              },
            ),
          DataGridAction(
            name: UserStrings.changePassword,
            action: (SingleDataGridController p0, [_]) =>
                UsersTabHelper.setPassword(context, p0),
            isEnabled: RightsService.canUpdateUnitUsers,
          ),
        ],
        columnHelp: UserColumns.columnHelp,
        columns: UserColumns.generateColumns(columnIdentifiers));

    return SingleTableDataGrid<UnitUserModel>(controller!);
  }
}
