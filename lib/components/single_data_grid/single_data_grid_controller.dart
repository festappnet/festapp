import 'dart:async';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:trina_grid/trina_grid.dart';
import 'pluto_abstract.dart';
import 'data_grid_action.dart';
import 'package:file_saver/file_saver.dart';

enum DataGridFirstColumn {
  none,
  delete,
  deleteAndDuplicate,
  deleteAndCheck,
  check
}

/// Options for CSV export.
class ExportOptions {
  final bool visible;
  final String fileName;

  ExportOptions({this.visible = true, required this.fileName});
}

class SingleDataGridController<T extends ITrinaRowModel> {
  HtmlSaveCoordinator? _htmlSave;
  HtmlSaveCoordinator get htmlSave => _htmlSave ??= HtmlSaveCoordinator();
  void disposeHtml() {
    _htmlSave?.dispose();
    _htmlSave = null;
  }

  Future<void> prepareHtmlRows() => htmlSave.prepareWhere((identity) => {
        ...updatedRows,
        ...newRows
      }.any((row) => row.key == identity.entity && !deletedRows.contains(row)));
  final ValueNotifier<int> reloadGeneration = ValueNotifier(0);
  ValueNotifier<Key> refreshKeyNotifier = ValueNotifier(UniqueKey());

  bool isGridLoaded = false;
  bool _autoRefreshing = false;
  final bool refreshOnTabActivation;
  late TrinaGridStateManager stateManager;
  bool get hasUnsavedChanges =>
      updatedRows.isNotEmpty ||
      deletedRows.isNotEmpty ||
      newRows.isNotEmpty ||
      (_htmlSave?.hasDraft ?? false) ||
      (isGridLoaded && stateManager.isEditing);

  /// Fetch first, then recheck drafts: edits can start while awaiting the server.
  Future<bool> reloadIfClean({bool Function()? canApply}) async {
    if (_autoRefreshing || !isGridLoaded || hasUnsavedChanges) return false;
    _autoRefreshing = true;
    try {
      final data = await loadData();
      if (!context.mounted ||
          hasUnsavedChanges ||
          (canApply != null && !canApply())) {
        return false;
      }
      final horizontal = stateManager.scroll.horizontalOffset;
      final vertical = stateManager.scroll.verticalOffset;
      final sorted =
          stateManager.columns.where((c) => !c.sort.isNone).firstOrNull;
      rows = data.map((item) {
        final row = item.toTrinaRow(context);
        row.cells[firstColumnTypeId] = TrinaCell(value: 'delete');
        return row;
      }).toList();
      applyDataToGrid();
      if (sorted != null) {
        if (sorted.sort.isAscending) {
          stateManager.sortAscending(sorted);
        } else {
          stateManager.sortDescending(sorted);
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted || !isGridLoaded) return;
        stateManager.scroll.horizontal?.jumpTo(
            horizontal.clamp(0, stateManager.scroll.maxScrollHorizontal));
        stateManager.scroll.vertical
            ?.jumpTo(vertical.clamp(0, stateManager.scroll.maxScrollVertical));
      });
      return true;
    } finally {
      _autoRefreshing = false;
    }
  }

  Set<TrinaRow> updatedRows = {};
  Set<TrinaRow> deletedRows = {};
  Set<TrinaRow> newRows = {};
  bool get hasPendingChanges =>
      updatedRows.isNotEmpty ||
      deletedRows.isNotEmpty ||
      newRows.isNotEmpty ||
      htmlSave.hasDraft;
  List<TrinaRow> rows = [];
  List<TrinaColumn> columns = [];
  final Future<List<T>> Function() loadData;
  final DataGridFirstColumn firstColumnType;
  final String idColumn;
  final T Function(Map<String, dynamic>) fromPlutoJson;
  final T Function()? getNewObject;
  final T Function(T)? copyObject;
  final BuildContext context;
  final DataGridActionsController? actionsExtended;
  final List<DataGridAction>? headerChildren;
  final ExportOptions? exportOptions;
  final bool Function(TrinaRow)? additionalRowPredicate;
  final Widget Function(BuildContext, SingleDataGridController<T>)?
      headerFilterBuilder;
  bool additionalFilterEnabled;
  int additionalFilterCount = 0;
  StreamSubscription<TrinaGridEvent>? _filterSubscription;
  bool _applyingFilter = false;

  Iterable<TrinaRow> get visibleCheckedRows =>
      stateManager.refRows.filterOrOriginalList
          .where((row) => row.checked == true);

  void attachRowFilter() {
    detachRowFilter();
    if (additionalRowPredicate == null) return;
    stateManager.setFilterOnlyEvent(true);
    _filterSubscription = stateManager.eventManager!.listener((event) {
      if (event is TrinaGridSetColumnFilterEvent) {
        stateManager.setFilterRows(event.filterRows);
        applyRowFilter();
      }
    });
  }

  void detachRowFilter() {
    _filterSubscription?.cancel();
    _filterSubscription = null;
  }

  void toggleAdditionalFilter(bool enabled) {
    additionalFilterEnabled = enabled;
    applyRowFilter(recount: false);
  }

  // Call only for data/native-filter changes, never hover/selection notifications.
  void applyRowFilter({bool recount = true}) {
    final predicate = additionalRowPredicate;
    if (predicate == null || !isGridLoaded || _applyingFilter) return;
    _applyingFilter = true;
    try {
      final native = FilterHelper.convertRowsToFilter(
        stateManager.filterRows,
        stateManager.refColumns.where((c) => c.enableFilterMenuItem).toList(),
      );
      if (recount) {
        additionalFilterCount = stateManager.refRows.originalList
            .where((row) => (native?.call(row) ?? true) && predicate(row))
            .length;
      }
      stateManager.refRows.setFilter(
        (row) =>
            (native?.call(row) ?? true) &&
            (!additionalFilterEnabled || predicate(row)),
      );
      final visible = stateManager.refRows.filterOrOriginalList.toSet();
      for (final row in stateManager.refRows.originalList) {
        if (row.checked == true && !visible.contains(row)) {
          row.setChecked(false);
        }
      }
      stateManager.notifyListeners();
    } finally {
      _applyingFilter = false;
    }
  }

  /// Localized plain-text explanations, keyed by column field.
  final Map<String, String> columnHelp;

  String firstColumnTypeId = "delete0";

  SingleDataGridController({
    required this.context,
    required this.loadData,
    required this.fromPlutoJson,
    required this.firstColumnType,
    required this.idColumn,
    required this.columns,
    this.refreshOnTabActivation = true,
    this.headerChildren,
    this.actionsExtended,
    this.getNewObject,
    this.copyObject,
    this.exportOptions,
    this.additionalRowPredicate,
    this.additionalFilterEnabled = false,
    this.headerFilterBuilder,
    Map<String, String> columnHelp = const {},
  }) : columnHelp = Map.unmodifiable(columnHelp);

  String getCsvSeparator(Locale locale) {
    final format = NumberFormat.decimalPattern(locale.toString());
    return (format.symbols.DECIMAL_SEP == ',') ? ';' : ',';
  }

  Future<void> downloadCsv(BuildContext context) async {
    final locale = Localizations.localeOf(context);
    final separator = getCsvSeparator(locale);

    final csvExport = TrinaGridExportCsv();
    final String csvData = await csvExport.export(
      stateManager: stateManager,
      includeHeaders: true,
      ignoreFixedRows: false,
      separator: separator,
    );

    // Add BOM (Byte Order Mark) to ensure proper UTF-8 recognition
    final List<int> dataBytes = [0xEF, 0xBB, 0xBF, ...utf8.encode(csvData)];

    // Save CSV file using FileSaver with correct encoding
    await FileSaver.instance.saveFile(
      name: exportOptions?.fileName ?? 'grid-export',
      bytes: Uint8List.fromList(dataBytes),
      fileExtension: 'csv',
      mimeType: MimeType.csv,
    );
  }

  /// Loads data and stores it in [rows] without modifying the grid.
  Future<void> loadDataOnly() async {
    var defaultRow = {firstColumnTypeId: TrinaCell(value: "delete")};
    final dataList = await loadData();
    var rowList = dataList.map((i) => i.toTrinaRow(context)).toList();
    for (var element in rowList) {
      element.cells.addAll(defaultRow);
    }
    rows = rowList;
    // Clear tracking sets.
    deletedRows.clear();
    newRows.clear();
    updatedRows.clear();
  }

  /// Applies [rows] to the grid and inserts the first column if needed.
  void applyDataToGrid() async {
    final sorted = additionalRowPredicate == null ? null : stateManager.columns.where((c) => !c.sort.isNone).firstOrNull;
    htmlSave.clearBindings();
    stateManager.removeAllRows();
    stateManager.appendRows(rows);
    if (sorted != null) {
      if (sorted.sort.isAscending) { stateManager.sortAscending(sorted); }
      else { stateManager.sortDescending(sorted); }
    }

    if (additionalRowPredicate != null) {
      applyRowFilter();
    } else if (stateManager.hasFilter) {
      stateManager.setFilterWithFilterRows(stateManager.filterRows);
    }

    if (stateManager.columns.isNotEmpty &&
        stateManager.columns.first.field != firstColumnTypeId &&
        firstColumnType != DataGridFirstColumn.none) {
      var firstColumn = TrinaColumn(
        title: "",
        field: firstColumnTypeId,
        type: TrinaColumnType.text(),
        readOnly: true,
        enableFilterMenuItem: false,
        enableSorting: false,
        enableDropToResize: false,
        enableColumnDrag: false,
        enableContextMenu: false,
        enableRowChecked:
            firstColumnType == DataGridFirstColumn.deleteAndCheck ||
                firstColumnType == DataGridFirstColumn.check,
        cellPadding: EdgeInsets.zero,
        width: (firstColumnType == DataGridFirstColumn.delete ||
                firstColumnType == DataGridFirstColumn.check)
            ? 50
            : 100,
        renderer: (rendererContext) {
          List<Widget> rowChildren = [];
          if (firstColumnType != DataGridFirstColumn.check) {
            rowChildren.add(
              IconButton(
                onPressed: () async {
                  var row = rendererContext.row;
                  if (deletedRows.contains(row)) {
                    deletedRows.remove(row);
                  } else if (newRows.contains(row)) {
                    newRows.remove(row);
                    rendererContext.stateManager.removeRows([row]);
                  } else {
                    deletedRows.add(row);
                  }
                  row.setState(TrinaRowState.updated);
                  applyRowFilter();
                  rendererContext.stateManager.notifyListeners();
                },
                icon: const Icon(Icons.delete_forever),
              ),
            );
          }
          if (firstColumnType == DataGridFirstColumn.deleteAndDuplicate) {
            rowChildren.add(
              IconButton(
                onPressed: () async {
                  var originRow = rendererContext.row;
                  var newRow = rendererContext.stateManager.getNewRows()[0];
                  if (copyObject != null) {
                    newRow = copyObject!(fromPlutoJson(originRow.toJson()))
                        .toTrinaRow(context);
                    var defaultRow = {
                      firstColumnTypeId: TrinaCell(value: "delete")
                    };
                    newRow.cells.addAll(defaultRow);
                  } else {
                    var readOnlyColumns = rendererContext.stateManager.columns
                        .where((element) => element.readOnly)
                        .map((e) => e.field)
                        .toList();
                    for (var c in originRow.cells.entries) {
                      if (readOnlyColumns.contains(c.key)) continue;
                      newRow.cells[c.key]?.value =
                          originRow.cells[c.key]?.value;
                    }
                  }

                  var currentIndex =
                      rendererContext.stateManager.rows.indexOf(originRow);
                  rendererContext.stateManager
                      .insertRows(currentIndex + 1, [newRow]);
                  newRows.add(newRow);
                  applyRowFilter();
                  rendererContext.stateManager.notifyListeners();
                },
                icon: const Icon(Icons.add),
              ),
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: rowChildren,
          );
        },
      );
      stateManager.insertColumns(0, [firstColumn]);
    }
  }

  /// Reloads the data from the source and applies it to the grid.
  Future<void> reloadData() async {
    await loadDataOnly();
    applyDataToGrid();
    reloadGeneration.value++;
  }

  /// Force-reloads the entire datagrid by updating the key and reloading data.
  Future<void> forceReload() async {
    await loadDataOnly();
    refreshKeyNotifier.value = UniqueKey();
    reloadGeneration.value++;
  }
}
