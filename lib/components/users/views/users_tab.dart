import 'package:flutter/material.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/features/import_feature.dart';
import 'package:fstapp/components/import/import_dialog_helper.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/i_has_id.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/views/users_tab_helper.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/companion/companion_admin_dialog.dart';
import 'package:fstapp/components/users/companion/admin_companion_relationships.dart';

class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  _UsersTabState createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab> {
  static bool get _hasCsmAppLinks => AppConfig.organization == 9;
  static bool get _canManageCompanions => RightsService.isEditor();

  static List<String> getColumnIdentifiers() {
    final identifiers = [
      UserColumns.ID,
      UserColumns.EMAIL,
      if (RightsService.isAdmin()) UserColumns.EMAIL_HISTORY,
      UserColumns.NAME,
      UserColumns.SURNAME,
      if (FeatureService.isFeatureEnabled(FeatureConstants.userGroups))
        UserColumns.GROUP,
      UserColumns.SEX,
      if (FeatureService.isServiceAccommodationEnabled())
        UserColumns.ACCOMMODATION,
      if (FeatureService.isFeatureEnabled(FeatureConstants.volunteers))
        UserColumns.IS_VOLUNTEER,
      UserColumns.MANAGER,
      UserColumns.EDITOR,
      UserColumns.EDITOR_VIEW,
      if (FeatureService.isFeatureEnabled(FeatureConstants.form))
        UserColumns.EDITOR_ORDER,
      if (FeatureService.isFeatureEnabled(FeatureConstants.form))
        UserColumns.EDITOR_ORDER_VIEW,
      if (FeatureService.isFeatureEnabled(FeatureConstants.entryCode))
        UserColumns.APPROVER,
      if (FeatureService.isFeatureEnabled(FeatureConstants.entryCode))
        UserColumns.APPROVED,
      if (FeatureService.isFeatureEnabled(FeatureConstants.cleaning))
        UserColumns.CLEANING_CREW,
      if (FeatureService.isFeatureEnabled(FeatureConstants.cleaning))
        UserColumns.CLEANING_BLOCKED,
      if (FeatureService.isFeatureEnabled(FeatureConstants.reception))
        UserColumns.RECEPTIONIST,
      UserColumns.INVITED,
      UserColumns.CREATED_AT,
      UserColumns.LAST_SIGN_IN_AT,
    ];

    final importFeature =
        FeatureService.getFeatureDetails(FeatureConstants.import)
            as ImportFeature?;
    if (importFeature != null &&
        importFeature.isEnabled &&
        importFeature.importFromTickets) {
      identifiers.addAll([
        UserColumns.ORDERED_AT,
        UserColumns.FORM,
      ]);
    }

    if (_hasCsmAppLinks) identifiers.add(UserColumns.APP_LINKS_SENT);

    return identifiers;
  }

  SingleDataGridController<OccasionUserModel>? controller;
  List<ServiceItemModel> _accommodations = [];

  Future<void> refreshData() async {
    await controller?.forceReload();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    controller ??= _createController();
  }

  Future<List<OccasionUserModel>> _loadUsersForGrid() async {
    final bundle = await DbUsers.getOccasionEditorDataBundle();
    annotateAdminCompanionRelationships(bundle.users);
    _accommodations =
        bundle.services[DbOccasions.serviceTypeAccommodation] ?? [];
    controller!.columns = UserColumns.generateColumns(
      getColumnIdentifiers(),
      data: {UserColumns.ACCOMMODATION: _accommodations},
    );
    return bundle.users;
  }

  SingleDataGridController<OccasionUserModel> _createController() {
    final headerActions = [
      if (RightsService.isManager())
        DataGridAction(
          name: CommonStrings.addExisting,
          action: (SingleDataGridController p0, [_]) async {
            await UsersTabHelper.addExisting(
                context,
                p0,
                (await DbUsers.getAllUsersBasics()).cast<IHasId>(),
                refreshData);
          },
        ),
      if (_hasCsmAppLinks)
        DataGridAction(
          name: UserStrings.sendAppLinks,
          requiresSelection: true,
          action: (SingleDataGridController p0, [_]) async {
            await UsersTabHelper.sendAppLinks(context, p0, refreshData);
          },
          isEnabled: RightsService.canUpdateUsers,
        ),
      DataGridAction(
        name: UserStrings.invite,
        requiresSelection: true,
        action: (SingleDataGridController p0, [_]) async {
          await UsersTabHelper.invite(context, p0, refreshData);
        },
        isEnabled: RightsService.canUpdateUsers,
      ),
      if (FeatureService.allowsAdminCompanionAssignment() &&
          _canManageCompanions)
        DataGridAction(
          name: UserStrings.manageCompanions,
          action: (SingleDataGridController p0, [_]) async {
            final selected = UsersTabHelper.getCheckedUsers(p0);
            if (selected.length != 1) return;
            await showDialog(
              context: context,
              builder: (_) => CompanionAdminDialog(
                owner: selected.single,
                users: p0.stateManager.refRows.originalList
                    .map((row) => OccasionUserModel.fromPlutoJson(row.toJson()))
                    .toList(growable: false),
                maxCompanions: FeatureService.getMaxCompanions(),
                onChanged: refreshData,
              ),
            );
          },
          isEnabled: () =>
              _canManageCompanions &&
              UsersTabHelper.getCheckedUsers(controller!).length == 1,
        ),
      DataGridAction(
        name: UserStrings.changePassword,
        requiresSelection: true,
        action: (SingleDataGridController p0, [_]) =>
            UsersTabHelper.setPassword(context, p0),
        isEnabled: RightsService.canUpdateUsers,
      ),
      if (FeatureService.isFeatureEnabled(FeatureConstants.import))
        DataGridAction(
          name: CommonStrings.import,
          action: (SingleDataGridController p0, [_]) async {
            await ImportDialogHelper.import(context);
            await refreshData();
          },
          isEnabled: RightsService.canUpdateUsers,
        ),
    ];

    return SingleDataGridController<OccasionUserModel>(
      context: context,
      loadData: _loadUsersForGrid,
      fromPlutoJson: OccasionUserModel.fromPlutoJson,
      getNewObject: () =>
          OccasionUserModel.newRow(RightsService.currentOccasionId()!),
      firstColumnType: DataGridFirstColumn.deleteAndCheck,
      idColumn: Tb.occasion_users.user,
      actionsExtended: DataGridActionsController(
        areAllActionsEnabled: RightsService.canUpdateUsers,
      ),
      headerChildren: headerActions,
      columnHelp: UserColumns.columnHelp,
      columns: UserColumns.generateColumns(
        getColumnIdentifiers(),
        data: {UserColumns.ACCOMMODATION: _accommodations},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<OccasionUserModel>(controller!);
  }
}
