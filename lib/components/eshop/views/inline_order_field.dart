import 'package:material_ui/material_ui.dart';

import '../../_shared/common_strings.dart';
import '../order_detail_controller.dart';
import '../order_detail_strings.dart';

/// One draft, one explicit field patch. Refreshes cannot overwrite an open draft.
class InlineOrderField extends StatefulWidget {
  const InlineOrderField({
    super.key,
    required this.label,
    required this.value,
    required this.displayValue,
    this.controller,
    this.canEdit,
    this.onSave,
    this.expectedFields,
    this.choices,
    this.multiline = false,
    this.alwaysEditable = false,
    this.textController,
  });
  final String label, value, displayValue;
  final OrderDetailController? controller;
  final bool Function()? canEdit;
  final Future<void> Function(String value, dynamic expectedFields)? onSave;
  final dynamic expectedFields;
  final List<String>? choices;
  final bool multiline;
  final bool alwaysEditable;

  /// Shared drafts (contact email) retain their existing controller/save owner.
  final TextEditingController? textController;
  @override
  State<InlineOrderField> createState() => _InlineOrderFieldState();
}

class _InlineOrderFieldState extends State<InlineOrderField> {
  late final _text = widget.textController ?? TextEditingController();
  final _draftKey = Object();
  bool _editing = false, _saving = false;
  String _original = '', _error = '';
  dynamic _expected;
  bool get _dirty => _editing && _text.text != _original;
  bool get _allowed =>
      (widget.onSave != null || widget.textController != null) &&
      (widget.canEdit?.call() ?? false);
  bool get _busy => _saving || (widget.controller?.busy ?? false);

  @override
  void initState() {
    super.initState();
    if (widget.alwaysEditable) {
      _editing = true;
      _original = widget.value;
      _text.text = widget.value;
      _expected = widget.expectedFields;
    }
    _text.addListener(_changed);
    if (widget.textController == null)
      widget.controller?.registerInlineDraft(
        _draftKey,
        isDirty: () => _dirty,
        discard: _discard,
        save: _save,
      );
  }

  @override
  void didUpdateWidget(covariant InlineOrderField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alwaysEditable && !_dirty) {
      _original = widget.value;
      _expected = widget.expectedFields;
      if (_text.text != widget.value) {
        _text.removeListener(_changed);
        _text.text = widget.value;
        _text.addListener(_changed);
      }
    }
  }

  void _changed() {
    if (mounted) setState(() {});
    widget.controller?.inlineDraftChanged();
  }

  void _discard() {
    if (!mounted || _saving) return;
    setState(() {
      _editing = widget.alwaysEditable;
      _original = widget.value;
      _error = '';
    });
    _text.text = widget.value;
  }

  @override
  void dispose() {
    if (widget.textController == null) {
      widget.controller?.unregisterInlineDraft(_draftKey);
      _text.dispose();
    } else {
      _text.removeListener(_changed);
    }
    super.dispose();
  }

  void _edit() {
    _original = widget.value;
    _expected = widget.expectedFields;
    if (widget.textController == null) _text.text = _original;
    setState(() {
      _editing = true;
      _error = '';
    });
  }

  Future<void> _save() async {
    if (!_dirty) return;
    if (_saving || !_allowed || widget.onSave == null)
      throw StateError(OrderDetailStrings.text('responses_unavailable'));
    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.onSave!(_text.text, _expected);
      if (!mounted) return;
      setState(() {
        _editing = widget.alwaysEditable;
        _original = _text.text;
      });
      widget.controller?.inlineDraftChanged();
    } catch (error) {
      if (mounted)
        setState(
          () => _error = error is StateError
              ? error.message.toString()
              : OrderDetailStrings.text('responses_unavailable'),
        );
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _value() {
    if (!_editing || (widget.alwaysEditable && !_allowed)) {
      return SelectableText(widget.displayValue);
    }
    if (widget.choices case final choices?) {
      return DropdownButtonFormField<String>(
        initialValue: choices.contains(_text.text) ? _text.text : null,
        isExpanded: true,
        decoration: InputDecoration(
          isDense: true,
          border: const OutlineInputBorder(),
          semanticCounterText: widget.label,
        ),
        items: [
          for (final choice in choices)
            DropdownMenuItem(value: choice, child: Text(choice)),
        ],
        onChanged: _busy || !_allowed
            ? null
            : (value) => _text.text = value ?? '',
      );
    }
    return Semantics(
      label: widget.label,
      child: TextField(
        controller: _text,
        autofocus: !widget.alwaysEditable,
        readOnly: _busy || !_allowed,
        minLines: 1,
        maxLines: widget.multiline ? null : 1,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  _value(),
                ],
              ),
            ),
            if (!_editing && _allowed)
              IconButton(
                tooltip: '${CommonStrings.edit}: ${widget.label}',
                onPressed: _busy ? null : _edit,
                icon: const Icon(Icons.edit_outlined, size: 18),
              ),
          ],
        ),
        if (_error.isNotEmpty)
          Text(
            _error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    ),
  );
}
