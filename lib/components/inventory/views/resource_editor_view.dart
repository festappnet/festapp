import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/models/resource_model.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/eshop/db_eshop.dart';
import 'package:trina_grid/trina_grid.dart';

import 'inventory_strings.dart';

class ResourceEditorView extends StatefulWidget {
  static const String RESOURCE_ID = "resourceId";
  static const String RESOURCE_TITLE = "resourceTitle";
  static const String RESOURCE_CAPACITY = "resourceCapacity";
  // Hidden fields
  static const String INVENTORY_POOL_ID_FIELD = "inventoryPoolId";
  static const String AGGREGATE_VERSION_FIELD =
      ResourceModel.aggregateVersionColumn;
  static const String OCCASION_ID_FIELD = "occasionId";

  final int inventoryPoolId;

  const ResourceEditorView({
    super.key,
    required this.inventoryPoolId,
  });

  @override
  State<ResourceEditorView> createState() => _ResourceEditorViewState();
}

class _ResourceEditorViewState extends State<ResourceEditorView> {
  late SingleDataGridController<ResourceModel> _gridController;

  @override
  void initState() {
    super.initState();
    _initializeGridController();
  }

  void _initializeGridController() {
    _gridController = SingleDataGridController<ResourceModel>(
      context: context,
      loadData: () =>
          DbEshop.getResourcesForInventoryPool(widget.inventoryPoolId),
      fromPlutoJson: ResourceModel.fromPlutoJson,
      idColumn: ResourceEditorView.RESOURCE_ID,
      firstColumnType: DataGridFirstColumn.deleteAndDuplicate,
      columns: _buildResourceColumns(),
      // When creating a new row, provide all required IDs
      getNewObject: () =>
          ResourceModel(inventoryPoolId: widget.inventoryPoolId, title: ""),
      copyObject: (ResourceModel r) => r.copyWith(id: -1),
    );
  }

  List<TrinaColumn> _buildResourceColumns() {
    return [
      TrinaColumn(
        hide: true,
        readOnly: true,
        enableEditingMode: false,
        title: InventoryStrings.gridId,
        field: ResourceEditorView.RESOURCE_ID,
        type: TrinaColumnType.number(defaultValue: -1),
        width: 50,
        renderer: DataGridHelper.idRenderer,
      ),
      TrinaColumn(
        hide: true,
        title: '',
        field: ResourceEditorView.INVENTORY_POOL_ID_FIELD,
        type: TrinaColumnType.number(),
        readOnly: true,
        width: 50,
      ),
      TrinaColumn(
        hide: true,
        title: '',
        field: ResourceEditorView.AGGREGATE_VERSION_FIELD,
        type: TrinaColumnType.number(defaultValue: 0),
        readOnly: true,
        width: 50,
      ),
      TrinaColumn(
        title: InventoryStrings.resourceEditorTitle,
        field: ResourceEditorView.RESOURCE_TITLE,
        type: TrinaColumnType.text(),
        enableAutoEditing: true,
        width: 200,
      ),
      TrinaColumn(
        title: InventoryStrings.resourceEditorCapacity,
        field: ResourceEditorView.RESOURCE_CAPACITY,
        type: TrinaColumnType.number(defaultValue: 1, negative: false),
        enableAutoEditing: true,
        width: 100,
        textAlign: TrinaColumnTextAlign.end,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return SingleTableDataGrid<ResourceModel>(_gridController);
  }
}
