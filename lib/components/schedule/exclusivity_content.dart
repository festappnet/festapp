import 'package:flutter/material.dart';
import 'package:festapp_core/program.dart';
import 'package:fstapp/components/schedule/exclusive_events_cell.dart';
import 'package:fstapp/components/single_data_grid/data_grid_helper.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/single_data_grid/single_table_data_grid.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/schedule/db_events.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:trina_grid/trina_grid.dart';

import 'exclusive_group_model.dart';

class ExclusivityContent extends StatefulWidget {
  const ExclusivityContent({super.key});

  @override
  _ExclusivityContentState createState() => _ExclusivityContentState();
}

class _ExclusivityContentState extends State<ExclusivityContent> {
  SingleDataGridController<ExclusiveGroupModel>? controller;

  // Event catalog for the picker cell: maps the stored event ids to titles
  // and times so the grid never shows raw ids.
  List<EventModel> _allEvents = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    try {
      _allEvents = await DbEvents.getAllEventsBasic();
    } catch (e) {
      AppLogger.error("Error loading events for ExclusivityContent: $e");
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// The cell keeps storing a comma-separated id list (the grid's save format);
  /// only the rendering and editing are name-based.
  static List<int> _parseIds(dynamic cellValue) =>
      cellValue
          .toString()
          .split(",")
          .map((e) => int.tryParse(e.trim()))
          .whereType<int>()
          .toList();

  void _initController() {
    controller ??= SingleDataGridController<ExclusiveGroupModel>(
      context: context,
      loadData: DbEvents.getAllExclusiveGroups,
      fromPlutoJson: ExclusiveGroupModel.fromPlutoJson,
      firstColumnType: DataGridFirstColumn.delete,
      idColumn: Tb.exclusive_groups.id,
      columns: [
        TrinaColumn(
          hide: true,
          title: CommonStrings.id,
          field: Tb.exclusive_groups.id,
          type: TrinaColumnType.number(defaultValue: -1),
          readOnly: true,
          enableEditingMode: false,
          width: 50,
          renderer: (rendererContext) =>
              DataGridHelper.idRenderer(rendererContext),
        ),
        TrinaColumn(
          title: CommonStrings.name,
          field: Tb.exclusive_groups.title,
          type: TrinaColumnType.text(),
          width: 300,
        ),
        TrinaColumn(
          title: CommonStrings.events,
          field: Tb.events.table,
          type: TrinaColumnType.text(),
          enableEditingMode: false,
          width: 500,
          renderer: (rendererContext) => ExclusiveEventsCell(
            allEvents: _allEvents,
            selectedIds: _parseIds(rendererContext.cell.value),
            onChanged: (ids) {
              final cell = rendererContext.row.cells[Tb.events.table]!;
              rendererContext.stateManager
                  .changeCellValue(cell, ids.join(","), force: true);
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    _initController();
    return SingleTableDataGrid<ExclusiveGroupModel>(controller!);
  }
}
