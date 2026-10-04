import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:trina_grid/trina_grid.dart';
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
  GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();
  final _buttonFocus = FocusNode();
  Timer? _dismissTimer;
  bool _tooltipActive = false;
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

  // Tooltip exposes only a global dismissal API. Replacing this local tooltip
  // disposes its overlay without closing unrelated tooltips elsewhere in the app.
  void _dismiss({bool restoreButtonFocus = false}) {
    _dismissTimer?.cancel();
    if (!mounted || !_tooltipActive) return;
    _tooltipActive = false;
    final restoreFocus = restoreButtonFocus && _buttonFocus.hasFocus;
    setState(() => _tooltipKey = GlobalKey<TooltipState>());
    if (restoreFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _buttonFocus.requestFocus();
      });
    }
  }

  void _show() {
    _tooltipActive = true;
    _tooltipKey.currentState?.ensureTooltipVisible();
    // ensureTooltipVisible is persistent in this SDK; showDuration alone does
    // not limit manual activation.
    _dismissTimer?.cancel();
    _dismissTimer = Timer(
      const Duration(seconds: 10),
      () => _dismiss(restoreButtonFocus: true),
    );
  }

  @override
  void dispose() {
    _manager.removeListener(_onGridChanged);
    _manager.scroll.horizontal?.removeOffsetChangedListener(_dismiss);
    _dismissTimer?.cancel();
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
            Focus(
              canRequestFocus: false,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  _dismiss(restoreButtonFocus: true);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _dismiss(),
                onHorizontalDragUpdate: (_) {},
                onHorizontalDragEnd: (_) {},
                child: MouseRegion(
                  onEnter: (_) => _tooltipActive = true,
                  child: Tooltip(
                    key: _tooltipKey,
                    message: widget.help,
                    excludeFromSemantics: true,
                    triggerMode: TooltipTriggerMode.manual,
                    waitDuration: const Duration(milliseconds: 350),
                    exitDuration: const Duration(milliseconds: 100),
                    showDuration: const Duration(seconds: 10),
                    constraints: BoxConstraints(
                      maxWidth: math.min(
                        360,
                        math.max(0, MediaQuery.sizeOf(context).width - 32),
                      ),
                    ),
                    child: Semantics(
                      label: '${column.title}: ${widget.help}',
                      child: IconButton(
                        focusNode: _buttonFocus,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: DataGridColumnHeader._hitSize,
                          height: DataGridColumnHeader._hitSize,
                        ),
                        iconSize: 18,
                        color: style.iconColor,
                        onPressed: _show,
                        icon: const Icon(Icons.info_outline),
                      ),
                    ),
                  ),
                ),
              ),
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
