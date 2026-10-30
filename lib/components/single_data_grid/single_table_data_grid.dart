import 'data_grid_number_format.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/app_logger.dart';
import 'package:fstapp/services/locale_date_time.dart';
import 'admin_tab_activity.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/components/html/rich_html_editor_controller.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:trina_grid/trina_grid.dart';
import 'data_grid_strings.dart';
import 'pluto_abstract.dart';
import 'single_data_grid_header.dart';
import 'package:fstapp/theme_config.dart';

import 'single_data_grid_controller.dart';
import 'data_grid_column_header.dart';

class SingleTableDataGrid<T extends ITrinaRowModel> extends StatefulWidget {
  final SingleDataGridController<T> controller;

  const SingleTableDataGrid(this.controller, {super.key, this.emptyMessage});

  final String? emptyMessage;

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
    // An uninitialized grid cannot use reloadIfClean: there is no state manager.
    if (!widget.controller.isGridLoaded) {
      if (_initialLoadError != null) await initialLoad();
      return;
    }
    final success = await ExceptionHandler.guard(context,
        futureFunction: () => widget.controller
            .reloadIfClean(canApply: () => mounted && _active));
    if (mounted) {
      setState(() => _refreshPending =
          success != true && widget.controller.hasUnsavedChanges);
    }
  }

  Object? _initialLoadError;
  bool _initialLoadInProgress = false;
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
    if (_initialLoadInProgress) return;
    _initialLoadInProgress = true;
    setState(() {
      isLoading = true;
      _initialLoadError = null;
      _refreshPending = false;
    });
    try {
      await widget.controller.loadDataOnly();
    } catch (error) {
      AppLogger.error('Data grid initial load failed: $error');
      if (mounted) _initialLoadError = error;
    } finally {
      _initialLoadInProgress = false;
      if (mounted) setState(() => isLoading = false);
    }
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

  Color? _pendingRowColor(TrinaRow row) {
    bool contains(Iterable<TrinaRow> rows) =>
        rows.any((item) => item.key == row.key);
    if (contains(widget.controller.deletedRows)) return Colors.redAccent;
    if (contains(widget.controller.updatedRows) ||
        contains(widget.controller.newRows)) {
      return Colors.amber;
    }
    return null;
  }

  Widget _buildDataGrid(BuildContext context) {
    if (isLoading) {
      return Center(child: CircularProgressIndicator());
    }

    final error = _initialLoadError;
    if (error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(ExceptionHandler.toFriendlyMessage(error)),
            TextButton(
                onPressed: initialLoad, child: Text(CommonStrings.retry)),
          ],
        ),
      );
    }

    final configuration = SingleDataGridHeader.defaultTrinaGridConfiguration(
      widget.controller.context,
      Localizations.localeOf(widget.controller.context).languageCode,
    );
    for (final column in widget.controller.columns) {
      withDisplayNumberFormatting(
          column, () => Localizations.localeOf(context).toString());
      if (column.formatter != null) continue;
      String locale() => Localizations.localeOf(context).toString();
      if (column.type is TrinaColumnTypeDate) {
        column.formatter = (value) => LocaleDateTime.dateCell(value, locale());
      } else if (column.type is TrinaColumnTypeDateTime) {
        column.formatter =
            (value) => LocaleDateTime.dateTimeCell(value, locale());
      } else if (column.type is TrinaColumnTypeTime) {
        column.formatter = (value) => LocaleDateTime.timeCell(value, locale());
      }
    }
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
              : Center(
                  child: Text(widget.emptyMessage ?? DataGridStrings.noItems)),
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
          rowColorCallback: (rowContext) =>
              _pendingRowColor(rowContext.row)?.withAlpha(77) ??
              Colors.transparent,
          rowWrapper: (context, rowWidget, row, manager) => ListenableBuilder(
            listenable: manager,
            child: rowWidget,
            builder: (context, child) {
              final color = _pendingRowColor(row) ?? Colors.transparent;
              // Paint above selection backgrounds so unsaved edits stay visible.
              return DecoratedBox(
                key: ValueKey('grid-row-change-${row.key}'),
                position: DecorationPosition.foreground,
                decoration: BoxDecoration(
                    border: Border(
                  left: BorderSide(color: color, width: 3),
                  bottom: BorderSide(color: color, width: 1),
                )),
                child: child,
              );
            },
          ),
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
