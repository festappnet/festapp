import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The shared information control for grid headers and editor help.
class InfoTooltipButton extends StatefulWidget {
  final String message;
  final String semanticLabel;
  final FocusNode? focusNode;
  final Color? color;

  const InfoTooltipButton({
    super.key,
    required this.message,
    required this.semanticLabel,
    this.focusNode,
    this.color,
  });

  @override
  State<InfoTooltipButton> createState() => InfoTooltipButtonState();
}

class InfoTooltipButtonState extends State<InfoTooltipButton> {
  GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();
  final _ownFocus = FocusNode();
  Timer? _dismissTimer;
  bool _tooltipActive = false;

  FocusNode get _buttonFocus => widget.focusNode ?? _ownFocus;

  // Replacing this local tooltip closes only its own overlay.
  void dismiss({bool restoreButtonFocus = false}) {
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
    // Manual activation is persistent in this SDK, so bound it explicitly.
    _dismissTimer?.cancel();
    _dismissTimer = Timer(
      const Duration(seconds: 10),
      () => dismiss(restoreButtonFocus: true),
    );
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _ownFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          dismiss(restoreButtonFocus: true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => dismiss(),
        onHorizontalDragUpdate: (_) {},
        onHorizontalDragEnd: (_) {},
        child: MouseRegion(
          onEnter: (_) => _tooltipActive = true,
          child: Tooltip(
            key: _tooltipKey,
            message: widget.message,
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
              label: widget.semanticLabel,
              child: IconButton(
                focusNode: _buttonFocus,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 40, height: 40),
                iconSize: 18,
                color: widget.color,
                onPressed: _show,
                icon: const Icon(Icons.info_outline),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
