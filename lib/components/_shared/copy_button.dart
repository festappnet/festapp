import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/services/exception_handler.dart';

import 'common_strings.dart';

/// Compact clipboard action with immediate, temporary success feedback.
class CopyButton extends StatefulWidget {
  final String value;
  const CopyButton({super.key, required this.value});

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _timer;
  GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  void _reset() {
    _timer?.cancel();
    _copied = false;
    _tooltipKey = GlobalKey<TooltipState>();
  }

  @override
  void didUpdateWidget(covariant CopyButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) _reset();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    final value = widget.value;
    final success = await ExceptionHandler.guardVoid(context,
        futureFunction: () => Clipboard.setData(ClipboardData(text: value)));
    if (!success || !mounted || widget.value != value) return;
    _timer?.cancel();
    setState(() {
      _copied = true;
      // Replace the hover tooltip so its already-visible overlay updates too.
      _tooltipKey = GlobalKey<TooltipState>();
    });
    final key = _tooltipKey;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _copied && key == _tooltipKey) {
        key.currentState?.ensureTooltipVisible();
      }
    });
    _timer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(_reset);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      key: _tooltipKey,
      message: _copied ? CommonStrings.copied : CommonStrings.copy,
      child: SizedBox(
        width: 24,
        height: 30,
        child: IconButton(
          onPressed: widget.value.isEmpty ? null : _copy,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          iconSize: 16,
          style: IconButton.styleFrom(
            foregroundColor: _copied
                ? (theme.brightness == Brightness.dark
                    ? Colors.greenAccent.shade400 : Colors.green.shade700)
                : theme.colorScheme.onSurfaceVariant,
            backgroundColor: Colors.transparent,
          ),
          icon: Icon(_copied ? Icons.check : Icons.copy),
        ),
      ),
    );
  }
}
