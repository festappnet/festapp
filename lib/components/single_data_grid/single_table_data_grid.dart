import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'data_grid_strings.dart';
import 'pluto_abstract.dart';
import 'single_data_grid_header.dart';
import 'package:collection/collection.dart';
import 'package:fstapp/theme_config.dart';

import 'single_data_grid_controller.dart';

class SingleTableDataGrid<T extends ITrinaRowModel> extends StatefulWidget {
  final SingleDataGridController<T> controller;

  const SingleTableDataGrid(this.controller, {super.key});

  @override
  _SingleTableDataGridState<T> createState() => _SingleTableDataGridState<T>();
}

class _SingleTableDataGridState<T extends ITrinaRowModel>
    extends State<SingleTableDataGrid<T>> {
  bool isLoading = true;
  bool isDataGridLoading = true;

  @override
  void initState() {
    super.initState();
    initialLoad();
  }

  Future<void> initialLoad() async {
    await widget.controller.loadDataOnly();
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) => HtmlEditingScope(
    coordinator: widget.controller.htmlSave, child: _buildGrid(context));

  @override
  void dispose() { widget.controller.disposeHtml(); super.dispose(); }

  Widget _buildGrid(BuildContext context) {
    return ValueListenableBuilder<Key>(
      valueListenable: widget.controller.refreshKeyNotifier,
      builder: (context, key, child) {
        return KeyedSubtree(
          key: key,
          child: _buildDataGrid(context),
        );
      },
    );
  }

  Widget _buildDataGrid(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ThemeConfig.whiteColor(widget.controller.context),
      ),
      // trina_grid's select-column popup editor calls ShadTheme.of(context),
      // so the grid must have a ShadTheme ancestor or every dropdown crashes.
      child: ShadTheme(
        data: ShadThemeData(
          brightness: ThemeConfig.isDarkMode(context)
              ? Brightness.dark
              : Brightness.light,
          colorScheme: ThemeConfig.isDarkMode(context)
              ? const ShadSlateColorScheme.dark()
              : const ShadSlateColorScheme.light(),
        ),
        child: TrinaGrid(
        noRowsWidget: isDataGridLoading
            ? null
            : Center(child: Text(DataGridStrings.noItems)),
        columns: widget.controller.columns,
        rows: [],
        onChanged: (TrinaGridOnChangedEvent event) {
          if (event.row.state == TrinaRowState.updated) {
            if (event.row.cells[widget.controller.idColumn]?.value != -1) {
              widget.controller.deletedRows.remove(event.row);
              if (!widget.controller.newRows.contains(event.row)) {
                widget.controller.updatedRows.add(event.row);
              }
            }
          }
        },
        onLoaded: (TrinaGridOnLoadedEvent event) {
          widget.controller.stateManager = event.stateManager;
          event.stateManager.setSelectingMode(TrinaGridSelectingMode.cell);
          event.stateManager.setShowColumnFilter(true);
          widget.controller.applyDataToGrid();
          isDataGridLoading = false;
          setState(() {});
        },
        rowColorCallback: (rowContext) {
          var row = widget.controller.deletedRows
              .firstWhereOrNull((element) => element.key == rowContext.row.key);
          if (row != null) {
            return Colors.redAccent.withOpacity(0.3);
          }
          row = widget.controller.updatedRows
              .firstWhereOrNull((element) => element.key == rowContext.row.key);
          if (row != null) {
            return Colors.orangeAccent.withOpacity(0.3);
          }
          row = widget.controller.newRows
              .firstWhereOrNull((element) => element.key == rowContext.row.key);
          if (row != null) {
            return Colors.orangeAccent.withOpacity(0.3);
          }
          return Colors.transparent;
        },
        createHeader: (stateManager) => SingleDataGridHeader(
          stateManager: stateManager,
          controller: widget.controller,
        ),
        configuration: SingleDataGridHeader.defaultTrinaGridConfiguration(
          widget.controller.context,
          Localizations.localeOf(widget.controller.context).languageCode,
        ),
        ),
      ),
    );
  }
}
