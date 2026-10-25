import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// Wheel stepping for a focused numeric TextField or TextFormField.
///
/// Uses EditableText's public user-edit API so the field keeps its own parsing,
/// validation and onChanged behavior. [onChanged] can commit fields which
/// normally commit only on submission. Unfocused fields leave scrolling alone.
class EditorNumberScroll extends StatelessWidget {
  const EditorNumberScroll({
    super.key,
    required this.child,
    this.enabled = true,
    this.step = 1,
    this.min,
    this.max,
    this.onChanged,
  }) : assert(step > 0 && step < double.infinity),
       assert(min == null || max == null || min <= max);

  final Widget child;
  final bool enabled;
  final double step;
  final double? min, max;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) => Listener(
    onPointerSignal: (event) {
      if (!enabled ||
          event is! PointerScrollEvent ||
          event.scrollDelta.dy == 0) {
        return;
      }
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return;
      var inside = false;
      focused.visitAncestorElements((element) {
        if (element == context) {
          inside = true;
          return false;
        }
        return true;
      });
      if (!inside) return;
      final editor = focused.findAncestorStateOfType<EditableTextState>();
      if (editor == null || editor.widget.readOnly) return;
      final value = editor.widget.controller.value;
      if (value.composing.isValid && !value.composing.isCollapsed) return;
      final current = double.tryParse(value.text.trim().replaceAll(',', '.'));
      if (current == null || !current.isFinite) return;
      GestureBinding.instance.pointerSignalResolver.register(event, (_) {
        if (!editor.mounted) return;
        final multiplier = HardwareKeyboard.instance.isShiftPressed ? 10 : 1;
        var next = current - event.scrollDelta.dy.sign * step * multiplier;
        next = next.clamp(min ?? -double.maxFinite, max ?? double.maxFinite);
        if (!next.isFinite || next == current) return;
        final text = next.abs() >= 1e21
            ? next.toString()
            : next.toStringAsFixed(6).replaceFirst(RegExp(r'\.?0+$'), '');
        editor.userUpdateTextEditingValue(
          TextEditingValue(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
          ),
          SelectionChangedCause.keyboard,
        );
        onChanged?.call();
      });
    },
    child: child,
  );
}
