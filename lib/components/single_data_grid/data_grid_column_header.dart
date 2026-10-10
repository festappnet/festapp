import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:trina_grid/trina_grid.dart';
import 'package:fstapp/widgets/info_tooltip_button.dart';
// TrinaGrid exports this public widget only through its UI library.
// ignore: implementation_imports
import 'package:trina_grid/src/ui/ui.dart' show CheckboxAllSelectionWidget;

/// Shared header for controller-owned columns with a plain-text explanation.
class DataGridColumnHeader extends StatefulWidget {
  final TrinaColumnTitleRendererContext rendererContext;
  final String help;

  const DataGridColumnHeader({
    required this.rendererContext,
    required this.help,
    super.key,
  });

  static final _installed = Expando<_InstalledHeader>();
  static const double _hitSize = 40;

  static bool _hasCheckbox(TrinaColumn column) =>
      column.enableRowChecked &&
      column.rowCheckBoxGroupDepth == 0 &&
      column.enableTitleChecked;

  /// Install immediately before constructing the grid, including after reload.
  /// Columns are mutable and must not be shared between live controllers.
  static void install(
    List<TrinaColumn> columns,
    Map<String, String> columnHelp,
    TrinaGridStyleConfig style,
  ) {
    for (final column in columns) {
      final help = columnHelp[column.field];
      if (help == null || help.trim().isEmpty) continue;
      final previous = _installed[column];
      if (column.titleRenderer != null &&
          column.titleRenderer != previous?.render) {
        throw StateError(
          'Column "${column.field}" has both columnHelp and a custom titleRenderer.',
        );
      }
      final installed =
          previous?.help == help ? previous! : _InstalledHeader(help);
      _installed[column] = installed;
      column.titleRenderer = installed.render;
      final padding = column.titlePadding ?? style.defaultColumnTitlePadding;
      // Reserve filter space before it becomes active. Sorting can expose the
      // context icon even when the menu and resizing are disabled.
      final filter = style.filterIconWidget != null || style.filterIcon != null;
      final context = column.enableContextMenu ||
          column.enableDropToResize ||
          column.enableSorting;
      final minimum = padding.horizontal +
          12 +
          _hitSize +
          (_hasCheckbox(column) ? _hitSize : 0) +
          (filter ? _hitSize : 0) +
          (context ? math.max(48, style.iconSize + 16) : 0);
      column.minWidth = math.max(column.minWidth, minimum);
      column.width = math.max(column.width, column.minWidth);
    }
  }

  @override
  State<DataGridColumnHeader> createState() => _DataGridColumnHeaderState();
}

class _InstalledHeader {
  final String help;
  _InstalledHeader(this.help);

  Widget render(TrinaColumnTitleRendererContext context) =>
      DataGridColumnHeader(
        key: ValueKey(context.column.key),
        rendererContext: context,
        help: help,
      );
}

class _DataGridColumnHeaderState extends State<DataGridColumnHeader> {
  final _helpKey = GlobalKey<InfoTooltipButtonState>();
  final _buttonFocus = FocusNode();
  TrinaCell? _lastCell;

  TrinaGridStateManager get _manager => widget.rendererContext.stateManager;

  @override
  void initState() {
    super.initState();
    _lastCell = _manager.currentCell;
    _buttonFocus.addListener(_onButtonFocus);
    _manager.addListener(_onGridChanged);
    _manager.scroll.horizontal?.addOffsetChangedListener(_dismiss);
  }

  void _onGridChanged() {
    // The library's keepFocus also considers descendant buttons focused.
    // Selecting a cell must return keyboard ownership to the grid itself.
    if (_manager.currentCell != _lastCell && _buttonFocus.hasFocus) {
      _manager.gridFocusNode.requestFocus();
    }
    _lastCell = _manager.currentCell;
    _dismiss();
    if (mounted) setState(() {});
  }

  void _onButtonFocus() {
    if (!_buttonFocus.hasFocus) return;
    // On entry TrinaGrid's FocusScope requests its cell focus. Complete the
    // requested header focus after that one-time request, preserving cell Tab.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _manager.gridFocusNode.hasPrimaryFocus) {
        _buttonFocus.requestFocus();
      }
    });
  }

  void _dismiss() => _helpKey.currentState?.dismiss();

  @override
  void dispose() {
    _manager.removeListener(_onGridChanged);
    _manager.scroll.horizontal?.removeOffsetChangedListener(_dismiss);
    _buttonFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final renderer = widget.rendererContext;
    final column = renderer.column;
    final style = _manager.style;
    final padding = column.titlePadding ?? style.defaultColumnTitlePadding;
    final filter = style.filterIconWidget ?? style.filterIcon;
    return Directionality(
      textDirection: _manager.textDirection,
      child: Container(
        height: renderer.height,
        width: column.width,
        padding: padding,
        decoration: BoxDecoration(
          color: column.backgroundColor,
          border: BorderDirectional(
            end: style.enableColumnBorderVertical
                ? BorderSide(color: style.borderColor)
                : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            if (DataGridColumnHeader._hasCheckbox(column))
              SizedBox(
                width: DataGridColumnHeader._hitSize,
                child: CheckboxAllSelectionWidget(stateManager: _manager),
              ),
            Expanded(
              child: Text.rich(
                column.titleSpan ?? TextSpan(text: column.title),
                style: style.columnTextStyle,
                textAlign: column.titleTextAlign.value,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            InfoTooltipButton(
              key: _helpKey,
              message: widget.help,
              semanticLabel: '${column.title}: ${widget.help}',
              focusNode: _buttonFocus,
              color: style.iconColor,
            ),
            if (_manager.isFilteredColumn(column) && filter != null)
              SizedBox(
                width: DataGridColumnHeader._hitSize,
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: style.filterIconWidget ??
                      Icon(
                        style.filterIcon!.icon,
                        size: style.iconSize,
                        color: style.filterHeaderIconColor ?? style.iconColor,
                      ),
                  onPressed: () => _manager.showFilterPopup(
                    context,
                    calledColumn: column,
                  ),
                ),
              ),
            if (renderer.showContextIcon) renderer.contextMenuIcon,
          ],
        ),
      ),
    );
  }
}

/// Visit help controls when entering a grid from surrounding page controls.
/// TrinaGrid continues to own Tab navigation while a data cell has focus.
class DataGridColumnHelpTraversalPolicy extends WidgetOrderTraversalPolicy {
  static bool _isHelp(FocusNode node) =>
      node.context?.findAncestorWidgetOfExactType<DataGridColumnHeader>() !=
      null;

  @override
  Iterable<FocusNode> sortDescendants(
    Iterable<FocusNode> descendants,
    FocusNode currentNode,
  ) {
    final ordered = super.sortDescendants(descendants, currentNode).toList();
    return [
      ...ordered.where(_isHelp),
      ...ordered.where((node) => !_isHelp(node)),
    ];
  }
}
