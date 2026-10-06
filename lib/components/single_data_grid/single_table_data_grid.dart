import 'admin_tab_activity.dart';
import 'package:fstapp/services/exception_handler.dart';
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
import 'data_grid_column_header.dart';

class SingleTableDataGrid<T extends ITrinaRowModel> extends StatefulWidget {
  final SingleDataGridController<T> controller;

  const SingleTableDataGrid(this.controller, {super.key});

  @override
  _SingleTableDataGridState<T> createState() => _SingleTableDataGridState<T>();
}

class _SingleTableDataGridState<T extends ITrinaRowModel>
    extends State<SingleTableDataGrid<T>> with AutomaticKeepAliveClientMixin {
  bool _active = true, _refreshPending = false;
  @override
  bool get wantKeepAlive => true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active = AdminTabActivity.isActive(context);
    if (active && !_active && widget.controller.refreshOnTabActivation) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _refreshOnReturn());
    }
    _active = active;
  }

  Future<void> _refreshOnReturn() async {
    if (!mounted || !_active) return;
    final success = await ExceptionHandler.guard(context,
        futureFunction: () => widget.controller
            .reloadIfClean(canApply: () => mounted && _active));
    if (mounted) setState(() => _refreshPending = success != true);
  }

  bool isLoading = true;
  bool isDataGridLoading = true;

  @override
  void initState() {
    super.initState();
    widget.controller.reloadGeneration.addListener(_explicitReloaded);
    initialLoad();
  }

  void _explicitReloaded() {
    if (mounted && _refreshPending) setState(() => _refreshPending = false);
  }

  Future<void> initialLoad() async {
    await widget.controller.loadDataOnly();
    if (!mounted) return;
    setState(() {
      isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return HtmlEditingScope(
        coordinator: widget.controller.htmlSave,
        child: Column(children: [
          if (_refreshPending)
            Padding(
                padding: const EdgeInsets.all(8),
                child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(DataGridStrings.refreshPending),
                      TextButton(
                          onPressed: _refreshOnReturn,
                          child: Text(DataGridStrings.refreshData)),
                    ])),
          Expanded(child: _buildGrid(context)),
        ]));
  }

  @override
  void dispose() {
    widget.controller.reloadGeneration.removeListener(_explicitReloaded);
    widget.controller.isGridLoaded = false;
    widget.controller.detachRowFilter();
    widget.controller.disposeHtml();
    super.dispose();
  }

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

  Widget _withColumnHelpTraversal(Widget grid) {
    final hasHelp = widget.controller.columns.any((column) =>
        widget.controller.columnHelp[column.field]?.trim().isNotEmpty ?? false);
    return hasHelp
        ? FocusTraversalGroup(
            policy: DataGridColumnHelpTraversalPolicy(),
            child: grid,
          )
        : grid;
  }

  Widget _buildDataGrid(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final configuration = SingleDataGridHeader.defaultTrinaGridConfiguration(
      widget.controller.context,
      Localizations.localeOf(widget.controller.context).languageCode,
    );
    DataGridColumnHeader.install(
      widget.controller.columns,
      widget.controller.columnHelp,
      configuration.style,
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: ThemeConfig.whiteColor(widget.controller.context),
      ),
      // Keep select-column popups consistent with the application's theme.
      child: ShadTheme(
        data: ShadThemeData(
          brightness: ThemeConfig.isDarkMode(context)
              ? Brightness.dark
              : Brightness.light,
          colorScheme: ThemeConfig.isDarkMode(context)
              ? const ShadSlateColorScheme.dark()
              : const ShadSlateColorScheme.light(),
        ),
        child: _withColumnHelpTraversal(TrinaGrid(
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
            widget.controller.applyRowFilter();
              widget.controller.stateManager.notifyListeners();
          },
          onLoaded: (TrinaGridOnLoadedEvent event) {
            widget.controller.stateManager = event.stateManager;
            widget.controller.isGridLoaded = true;
            event.stateManager.setSelectingMode(TrinaGridSelectingMode.cell);
            event.stateManager.setShowColumnFilter(true);
            widget.controller.attachRowFilter();
            widget.controller.applyDataToGrid();
            isDataGridLoading = false;
            setState(() {});
          },
          rowColorCallback: (rowContext) {
            var row = widget.controller.deletedRows.firstWhereOrNull(
                (element) => element.key == rowContext.row.key);
            if (row != null) {
              return Colors.redAccent.withOpacity(0.3);
            }
            row = widget.controller.updatedRows.firstWhereOrNull(
                (element) => element.key == rowContext.row.key);
            if (row != null) {
              return Colors.orangeAccent.withOpacity(0.3);
            }
            row = widget.controller.newRows.firstWhereOrNull(
                (element) => element.key == rowContext.row.key);
            if (row != null) {
              return Colors.orangeAccent.withOpacity(0.3);
            }
            return Colors.transparent;
          },
          createHeader: (stateManager) => SingleDataGridHeader(
            stateManager: stateManager,
            controller: widget.controller,
          ),
          configuration: configuration,
        )),
      ),
    );
  }
}
