import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import '../../editor_ui/editor_field_history.dart';

/// A transient text draft. The editor owns the eventual undo transaction.
class LayoutInlineLabel extends StatefulWidget {
  const LayoutInlineLabel({
    super.key,
    required this.value,
    required this.style,
    required this.onSubmit,
    required this.onCancel,
    this.onUndo,
    this.onRedo,
    this.textAlign = TextAlign.center,
    this.background = Colors.white,
  });
  final String value;
  final TextStyle style;
  final TextAlign textAlign;
  final Color background;
  final ValueChanged<String> onSubmit;
  final VoidCallback onCancel;
  final VoidCallback? onUndo, onRedo;
  @override
  State<LayoutInlineLabel> createState() => _LayoutInlineLabelState();
}

class _LayoutInlineLabelState extends State<LayoutInlineLabel> {
  late final _text = TextEditingController(text: widget.value)
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.value.length,
    );
  final _focus = FocusNode();
  bool _finished = false, _blurPending = false;
  bool get _composing =>
      _text.value.composing.isValid && !_text.value.composing.isCollapsed;
  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
    _text.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_finished) _focus.requestFocus();
    });
  }

  void _focusChanged() {
    if (!_focus.hasFocus) {
      _blurPending = true;
      _finish();
    }
  }

  void _changed() {
    if (_blurPending && !_composing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finish();
      });
    }
  }

  void _finish() {
    if (_finished || _composing) return;
    _finished = true;
    widget.onSubmit(_text.text);
  }

  @override
  void dispose() {
    _focus.removeListener(_focusChanged);
    _text.removeListener(_changed);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    child: Focus(
      includeSemantics: false,
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape) {
          _finished = true;
          widget.onCancel();
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter &&
            !HardwareKeyboard.instance.isShiftPressed &&
            !_composing) {
          _finish();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: Colors.transparent,
        child: EditorFieldHistory(
          hasUncommittedChanges: () => _text.text != widget.value || _composing,
          onUndo: () {
            _finished = true;
            widget.onUndo?.call();
          },
          onRedo: () {
            _finished = true;
            widget.onRedo?.call();
          },
          child: TextField(
            key: const ValueKey('layout-inline-label'),
            controller: _text,
            focusNode: _focus,
            autofocus: true,
            style: widget.style,
            textAlign: widget.textAlign,
            textAlignVertical: TextAlignVertical.center,
            expands: true,
            maxLines: null,
            minLines: null,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: widget.background,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 3,
                vertical: 2,
              ),
              border: const OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.primary,
                  width: 1,
                ),
              ),
            ),
            onTapOutside: (_) => _focus.unfocus(),
          ),
        ),
      ),
    ),
  );
}
