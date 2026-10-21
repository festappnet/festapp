import 'package:flutter/material.dart';
import 'package:fstapp/components/single_data_grid/data_grid_action.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/occasion_services/service_item_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/occasion/db_occasions.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/users/user_columns.dart';
import 'package:fstapp/components/occasion_services/service_dialog.dart';
import 'package:fstapp/components/occasion_services/occasion_services_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:trina_grid/trina_grid.dart';

class ServiceTab extends StatefulWidget {
  const ServiceTab({super.key});

  @override
  _ServiceTabState createState() => _ServiceTabState();
}

class _ServiceTabState extends State<ServiceTab> {
  /// Whether the occasion's ServicesFeature permits accommodation management.
  bool get _allowAccommodation =>
      FeatureService.isServiceAccommodationEnabled();

  /// Whether the occasion's ServicesFeature permits food/diet management.
  bool get _allowFood => FeatureService.isServiceFoodEnabled();

  /// Grid columns limited to what the ServicesFeature permits. Accommodation
  /// and food/diet columns are only included when their setting is enabled.
  List<String> get _columnIdentifiers => [
        UserColumns.ID,
        UserColumns.EMAIL,
        UserColumns.NAME,
        UserColumns.SURNAME,
        if (_allowAccommodation) UserColumns.ACCOMMODATION,
        if (_allowFood) ...[
          UserColumns.FOOD,
          UserColumns.DIET,
        ],
        UserColumns.NOTE,
      ];

  List<ServiceItemModel> allFood = [];
  List<ServiceItemModel> allAccommodation = [];
  SingleDataGridController<OccasionUserModel>? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= _createController();
  }

  /// Loads the complete editor bundle in one RPC call for every grid reload.
  Future<List<OccasionUserModel>> _loadUsersForGrid() async {
    final bundle = await DbUsers.getOccasionEditorDataBundle();
    allFood = bundle.services[DbOccasions.serviceTypeFood] ?? [];
    allAccommodation =
        bundle.services[DbOccasions.serviceTypeAccommodation] ?? [];
    _controller!.columns = _buildColumns();
    return bundle.users;
  }

  List<TrinaColumn> _buildColumns() => UserColumns.generateColumns(
        _columnIdentifiers,
        data: {
          UserColumns.FOOD: allFood,
          UserColumns.ACCOMMODATION: allAccommodation,
        },
      );

  SingleDataGridController<OccasionUserModel> _createController() =>
      SingleDataGridController<OccasionUserModel>(
        context: context,
        loadData: _loadUsersForGrid,
        fromPlutoJson: OccasionUserModel.fromPlutoJson,
        firstColumnType: DataGridFirstColumn.none,
        idColumn: Tb.occasion_users.user,
        actionsExtended: DataGridActionsController(
          areAllActionsEnabled: RightsService.canUpdateUsers,
          isAddActionPossible: () => false,
        ),
        headerChildren: [
          if (_allowAccommodation)
            DataGridAction(
              name: OccasionServicesStrings.accommodationSettings,
              action: (SingleDataGridController p0, [_]) =>
                  _accommodationDefinition(p0),
              isEnabled: RightsService.isManager,
            ),
          if (_allowFood)
            DataGridAction(
              name: OccasionServicesStrings.foodSettings,
              action: (SingleDataGridController p0, [_]) => _foodDefinition(p0),
              isEnabled: RightsService.isManager,
            ),
        ],
        columns: _buildColumns(),
      );

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<OccasionUserModel>(_controller!);
  }

  Future<void> _accommodationDefinition(
      SingleDataGridController<ITrinaRowModel> controller) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return ServiceDialog(
          type: DbOccasions.serviceTypeAccommodation,
          title: OccasionServicesStrings.accommodation,
          description: OccasionServicesStrings.accommodationCreateHint,
          referenceString: CommonStrings.place,
        );
      },
    );

    await _controller!.forceReload();
  }

  Future<void> _foodDefinition(
      SingleDataGridController<ITrinaRowModel> controller) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return ServiceDialog(
          type: DbOccasions.serviceTypeFood,
          title: CommonStrings.food,
          description: OccasionServicesStrings.foodCreateHint,
          referenceString: CommonStrings.event,
        );
      },
    );

    await _controller!.forceReload();
  }
}
