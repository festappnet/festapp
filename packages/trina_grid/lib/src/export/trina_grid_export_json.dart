import 'dart:convert'; // Import for JSON encoding
import 'package:trina_grid/src/export/trina_grid_export.dart';
import 'package:trina_grid/src/manager/trina_grid_state_manager.dart';
import 'package:trina_grid/src/model/trina_column.dart';
import 'package:trina_grid/src/model/trina_row.dart';

/// Implementation of JSON export for Trina Grid
class TrinaGridExportJson implements TrinaGridExport {
  @override
  Future<String> export({
    required TrinaGridStateManager stateManager,
    List<String>? columns,
    bool includeHeaders = true,
    bool ignoreFixedRows = false,
  }) async {
    // Get columns to export
    final List<TrinaColumn> columnsToExport = _getColumnsToExport(
      stateManager: stateManager,
      columnNames: columns,
    );

    if (columnsToExport.isEmpty) {
      throw Exception('No columns to export');
    }

    // Get rows
    final List<TrinaRow> rows = stateManager.refRows;

    // Create JSON content
    final List<Map<String, dynamic>> jsonData = [];

    if (includeHeaders) {
      final Map<String, dynamic> rowData = {};
      for (final column in columnsToExport) {
        rowData[column.field] = column.title;
      }
      jsonData.add(rowData);
    }

    // Add data rows
    for (final row in rows) {
      if (ignoreFixedRows && row.frozen != TrinaRowFrozen.none) {
        continue;
      }
      final Map<String, dynamic> rowData = {};
      for (final column in columnsToExport) {
        final cell = row.cells[column.field];
        final value = cell?.value ?? '';
        rowData[column.field] = value; // Use column title as key
      }
      jsonData.add(rowData);
    }

    return json.encode(jsonData); // Convert to JSON string
  }

  /// Helper method to get the columns to export based on provided column names
  /// or visible columns if no column names are provided
  List<TrinaColumn> _getColumnsToExport({
    required TrinaGridStateManager stateManager,
    List<String>? columnNames,
  }) {
    if (columnNames == null || columnNames.isEmpty) {
      // If no columns specified, use all visible columns
      return stateManager.columns;
    } else {
      // Filter columns by the provided column names
      return stateManager.refColumns
          .where((column) => columnNames.contains(column.title))
          .toList();
    }
  }
}
