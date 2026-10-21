import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../_shared/common_strings.dart';

/// Edits one commercial label as a local draft, preserving the panel context.
class BlueprintInlineName extends StatefulWidget {
  const BlueprintInlineName({
    super.key,
    required this.nodeId,
    required this.name,
    required this.enabled,
    required this.onSubmitted,
    this.style,
  });

  final String nodeId;
  final String name;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  final TextStyle? style;

  @override
  State<BlueprintInlineName> createState() => _BlueprintInlineNameState();
}

class _BlueprintInlineNameState extends State<BlueprintInlineName> {
  final _text = TextEditingController();
  bool _editing = false;

  void _finish({bool cancel = false}) {
    if (!_editing) return;
    final value = _text.text.trim();
    setState(() => _editing = false);
    if (!cancel && widget.enabled && value.isNotEmpty && value != widget.name) {
      widget.onSubmitted(value);
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_editing) {
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _finish(cancel: true),
        },
        child: Focus(
          onFocusChange: (focused) {
            if (!focused) _finish();
          },
          child: TextField(
            key: ValueKey('commercial-name-field-${widget.nodeId}'),
            controller: _text,
            autofocus: true,
            enabled: widget.enabled,
            style: widget.style,
            decoration: InputDecoration(labelText: CommonStrings.name),
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _finish(),
            onTapOutside: (_) => _finish(),
          ),
        ),
      );
    }
    return Row(children: [
      Expanded(child: Text(widget.name, style: widget.style)),
      if (widget.enabled)
        IconButton(
          key: ValueKey('rename-commercial-${widget.nodeId}'),
          tooltip: CommonStrings.rename,
          icon: const Icon(Icons.edit_outlined, size: 18),
          onPressed: () {
            _text.text = widget.name;
            _text.selection =
                TextSelection(baseOffset: 0, extentOffset: _text.text.length);
            setState(() => _editing = true);
          },
        ),
    ]);
  }
}
