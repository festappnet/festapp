import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../order_detail_strings.dart';
import '../../single_data_grid/single_data_grid_header.dart';

/// Retains both workspaces while the detail width changes. Only the user-chosen
/// width is stored; responsive clamping never overwrites their desktop choice.
class OrderDetailSplitPane extends StatefulWidget {
  const OrderDetailSplitPane({super.key, required this.table, this.detail});
  final Widget table;
  final Widget? detail;
  static const preferenceKey = 'festapp.orderDetail.paneWidth';
  static const minDetailWidth = 360.0,
      maxDetailWidth = 760.0,
      minTableWidth = 480.0;
  @override
  State<OrderDetailSplitPane> createState() => _OrderDetailSplitPaneState();
}

class _OrderDetailSplitPaneState extends State<OrderDetailSplitPane>
    with WidgetsBindingObserver {
  final _dividerFocus = FocusNode();
  double _preferredWidth = 600;
  bool _changed = false;
  int? _dragPointer;
  double _dragLastX = 0, _dragWidth = 0;
  OverlayEntry? _dragCursor;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final width = prefs.getDouble(OrderDetailSplitPane.preferenceKey);
      if (mounted && !_changed && width != null && width.isFinite)
        setState(
          () => _preferredWidth = width.clamp(
            OrderDetailSplitPane.minDetailWidth,
            OrderDetailSplitPane.maxDetailWidth,
          ),
        );
    } catch (_) {
      /* A local preference failure must not block order access. */
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(
        OrderDetailSplitPane.preferenceKey,
        _preferredWidth,
      );
    } catch (_) {
      /* The current session still retains the chosen width. */
    }
  }

  void _resize(double width, double maximum) {
    setState(() {
      _changed = true;
      _preferredWidth = width.clamp(
        OrderDetailSplitPane.minDetailWidth,
        maximum,
      );
    });
  }

  void _finishDrag() {
    if (_dragPointer == null) return;
    _dragPointer = null;
    _removeDragCursor();
    _persist();
  }

  void _removeDragCursor() {
    _dragCursor?.remove();
    _dragCursor?.dispose();
    _dragCursor = null;
  }

  void _startDrag(PointerDownEvent event, double panelWidth) {
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    _finishDrag();
    _dividerFocus.requestFocus();
    _dragPointer = event.pointer;
    _dragLastX = event.position.dx;
    _dragWidth = panelWidth;
    // The pointer remains captured outside the idle hit target. Its cursor
    // must follow that same lifecycle, including beyond the width limits.
    _dragCursor = OverlayEntry(
      builder: (_) => Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          hitTestBehavior: HitTestBehavior.opaque,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerHover: (_) => _finishDrag(),
            onPointerDown: (_) => _finishDrag(),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_dragCursor!);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _finishDrag();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _finishDrag();
    _removeDragCursor();
    _dividerFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const dividerWidth = 1.0;
      const dividerHitWidth = 40.0;
      final available = constraints.maxWidth;
      final side =
          widget.detail != null &&
          available >=
              OrderDetailSplitPane.minTableWidth +
                  OrderDetailSplitPane.minDetailWidth +
                  dividerWidth;
      final maximum =
          (available - OrderDetailSplitPane.minTableWidth - dividerWidth).clamp(
            OrderDetailSplitPane.minDetailWidth,
            OrderDetailSplitPane.maxDetailWidth,
          );
      final panelWidth = side
          ? _preferredWidth.clamp(OrderDetailSplitPane.minDetailWidth, maximum)
          : available;
      final tableWidth = side
          ? available - panelWidth - dividerWidth
          : available;
      void step(double delta) {
        _resize(panelWidth + delta, maximum);
        _persist();
      }

      final border = SingleDataGridHeader.defaultTrinaGridConfiguration(
        context,
        Localizations.localeOf(context).languageCode,
      ).style.borderColor;
      return Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Offstage(
                  offstage: widget.detail != null && !side,
                  child: TickerMode(
                    enabled: widget.detail == null || side,
                    child: OverflowBox(
                      minWidth: tableWidth,
                      maxWidth: tableWidth,
                      alignment: Alignment.topLeft,
                      child: widget.table,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: side ? dividerWidth : 0,
                child: side
                    ? ColoredBox(
                        key: const ValueKey('order-detail-divider-line'),
                        color: border,
                        child: const SizedBox.expand(),
                      )
                    : null,
              ),
              if (widget.detail != null)
                SizedBox(
                  key: const ValueKey('order-detail-pane'),
                  width: panelWidth,
                  child: widget.detail,
                ),
            ],
          ),
          if (side)
            Positioned(
              left: tableWidth + dividerWidth / 2 - dividerHitWidth / 2,
              top: 0,
              bottom: 0,
              width: dividerHitWidth,
              child: Semantics(
                // The web slider is a native range input with its own cursor.
                // Keep its accessible actions, but let Flutter own mouse hits.
                hitTestBehavior: ui.SemanticsHitTestBehavior.transparent,
                label: OrderDetailStrings.text('resize_panel'),
                slider: true,
                value: '${panelWidth.round()}',
                increasedValue:
                    '${(panelWidth + 32).clamp(OrderDetailSplitPane.minDetailWidth, maximum).round()}',
                decreasedValue:
                    '${(panelWidth - 32).clamp(OrderDetailSplitPane.minDetailWidth, maximum).round()}',
                onIncrease: () => step(32),
                onDecrease: () => step(-32),
                child: Focus(
                  focusNode: _dividerFocus,
                  onKeyEvent: (_, event) {
                    if (event is! KeyDownEvent) return KeyEventResult.ignored;
                    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
                      step(32);
                      return KeyEventResult.handled;
                    }
                    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
                      step(-32);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.resizeLeftRight,
                    child: Listener(
                      key: const ValueKey('order-detail-resize'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: (event) => _startDrag(event, panelWidth),
                      onPointerMove: (event) {
                        if (event.pointer != _dragPointer) return;
                        if ((event.buttons & kPrimaryMouseButton) == 0) {
                          _finishDrag();
                          return;
                        }
                        final delta = event.position.dx - _dragLastX;
                        _dragLastX = event.position.dx;
                        if (delta != 0) {
                          _resize(_dragWidth - delta, maximum);
                          _dragWidth = _preferredWidth;
                        }
                      },
                      onPointerUp: (event) {
                        if (event.pointer == _dragPointer) _finishDrag();
                      },
                      onPointerCancel: (event) {
                        if (event.pointer == _dragPointer) _finishDrag();
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}
