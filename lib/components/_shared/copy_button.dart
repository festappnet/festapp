import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:fstapp/widgets/app_dialog.dart';

import 'common_strings.dart';

/// Compact clipboard action with immediate, temporary success feedback.
class CopyButton extends StatefulWidget {
  final String value;
  final bool showLabel;
  const CopyButton({super.key, required this.value, this.showLabel = false});

  /// Canonical clipboard action for widgets and menu commands. Returns true
  /// only after a successful system write; denied access offers manual copying.
  static Future<bool> copy(BuildContext context, String value) async {
    if (value.isEmpty) return false;
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } on PlatformException {
      if (!context.mounted) return false;
      final controller = TextEditingController(text: value)
        ..selection = TextSelection(baseOffset: 0, extentOffset: value.length);
      final route = DialogRoute<void>(
          context: context,
          builder: (dialogContext) => AppAlertDialog(
                title: Text(CommonStrings.copyManually),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(CommonStrings.clipboardUnavailable),
                      const SizedBox(height: 16),
                      TextField(
                          controller: controller,
                          autofocus: true,
                          readOnly: true,
                          enableInteractiveSelection: true,
                          minLines: 1,
                          maxLines: 4),
                    ]),
              ));
      await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
      controller.dispose();
      return false;
    }
    return true;
  }

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
    if (!await CopyButton.copy(context, value)) return;
    if (!mounted || widget.value != value) return;
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
      child: widget.showLabel
          ? OutlinedButton.icon(
              onPressed: widget.value.isEmpty ? null : _copy,
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
              label: Text(_copied ? CommonStrings.copied : CommonStrings.copy),
            )
          : SizedBox(
              width: 24,
              height: 30,
              child: IconButton(
                onPressed: widget.value.isEmpty ? null : _copy,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                iconSize: 16,
                style: IconButton.styleFrom(
                  foregroundColor: _copied
                      ? (theme.brightness == Brightness.dark
                          ? Colors.greenAccent.shade400
                          : Colors.green.shade700)
                      : theme.colorScheme.onSurfaceVariant,
                  backgroundColor: Colors.transparent,
                ),
                icon: Icon(_copied ? Icons.check : Icons.copy),
              ),
            ),
    );
  }
}
