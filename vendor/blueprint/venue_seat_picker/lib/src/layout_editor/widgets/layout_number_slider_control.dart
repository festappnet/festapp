import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:venue_seat_picker/venue_seat_picker.dart';
import 'package:venue_seat_picker/editor_ui.dart';

/// Shared live numeric preview with one history operation per drag.
class LayoutNumberSliderControl extends StatefulWidget {
  const LayoutNumberSliderControl({
    super.key,
    required this.controller,
    required this.node,
    required this.value,
    required this.updateDocument,
    required this.label,
    required this.min,
    required this.max,
    this.rangeMin = 0,
    this.rangeMax = 160,
    this.wholeNumbers = false,
    this.onReset,
  });
  final VenueLayoutController controller;
  final LayoutNode node;
  final double value;
  final String label;
  final double min, max, rangeMin, rangeMax;
  final bool wholeNumbers;
  final VoidCallback? onReset;
  final VenueLayoutDocument Function(VenueLayoutDocument, double)
  updateDocument;
  @override
  State<LayoutNumberSliderControl> createState() =>
      _LayoutNumberSliderControlState();
}

class _LayoutNumberSliderControlState extends State<LayoutNumberSliderControl> {
  late final _text = TextEditingController(text: _display(widget.value));
  final _focus = FocusNode();
  VenueLayoutDocument? _baseline, _lastPreview;
  double? _dragMin, _dragMax;
  String? _error;
  bool _cancelled = false;
  bool _edited = false;
  bool get _enabled =>
      !widget.controller.readOnly &&
      !widget.controller.saving &&
      !widget.node.locked;
  String _display(double value) => widget.wholeNumbers
      ? value.round().toString()
      : value.toString().replaceFirst(RegExp(r'\.0$'), '');
  double get _min =>
      _dragMin ?? math.min(widget.rangeMin, widget.value).toDouble();
  double get _max =>
      _dragMax ??
      math.min(widget.max, math.max(widget.rangeMax, widget.value * 1.5));

  @override
  void initState() {
    super.initState();
    _focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!_focus.hasFocus) _submit();
  }

  @override
  void didUpdateWidget(LayoutNumberSliderControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _text.text = _display(widget.value);
      _edited = false;
    }
  }

  VenueLayoutDocument _sizedDocument(
    VenueLayoutDocument document,
    double value,
  ) => widget.updateDocument(document, value);

  void _start(double _) {
    if (!_enabled) return;
    _cancelled = false;
    _dragMin = _min;
    _dragMax = _max;
    _baseline = widget.controller.document;
    _lastPreview = _baseline;
    widget.controller.beginGesture();
  }

  void _change(double value) {
    if (!_enabled || _cancelled) return;
    final rounded = widget.wholeNumbers
        ? value.roundToDouble()
        : (value * 10).round() / 10;
    final baseline = _baseline;
    if (baseline == null) {
      widget.controller.apply(
        _sizedDocument(widget.controller.document, rounded),
        label: widget.label,
      );
    } else {
      widget.controller.preview(_sizedDocument(baseline, rounded));
      _lastPreview = widget.controller.document;
    }
  }

  void _finish(double _) {
    // Pointer cancellation reaches the parent Listener in the same event; defer
    // committing so cancellation can still restore the preview baseline.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _baseline == null) return;
      _baseline = null;
      _lastPreview = null;
      _dragMin = null;
      _dragMax = null;
      widget.controller.commitGesture();
    });
  }

  void _cancel() {
    if (_baseline == null) return;
    _cancelled = true;
    _baseline = null;
    _lastPreview = null;
    _dragMin = null;
    _dragMax = null;
    widget.controller.cancelGesture();
  }

  void _reset() {
    if (!_enabled) return;
    _cancel();
    widget.onReset?.call();
  }

  void _submit() {
    if (!_enabled || !_edited) return;
    final value = double.tryParse(_text.text.replaceAll(',', '.'));
    if (value == null ||
        !value.isFinite ||
        value < widget.min ||
        value > widget.max) {
      setState(
        () =>
            _error = VenueLayoutStrings.text(context, 'Enter a valid number.'),
      );
      return;
    }
    setState(() => _error = null);
    final rounded = widget.wholeNumbers ? value.roundToDouble() : value;
    _edited = false;
    _text.text = _display(rounded);
    if (rounded != widget.value) {
      widget.controller.apply(
        _sizedDocument(widget.controller.document, rounded),
        label: widget.label,
      );
    }
  }

  @override
  void dispose() {
    final c = widget.controller, preview = _lastPreview;
    if (_baseline != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (identical(c.document, preview)) c.cancelGesture();
      });
    }
    _focus.removeListener(_focusChanged);
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    onKeyEvent: (_, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape &&
          _baseline != null) {
        _cancel();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: double.infinity,
            child: EditorFieldHistory(
              hasUncommittedChanges: () => _edited,
              onUndo: widget.controller.undo,
              onRedo: widget.controller.redo,
              child: EditorNumberScroll(
                enabled: _enabled,
                min: widget.min,
                max: widget.max,
                onChanged: _submit,
                child: TextField(
                  controller: _text,
                  focusNode: _focus,
                  enabled: _enabled,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: VenueLayoutStrings.text(context, widget.label),
                    errorText: _error,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => _edited = true,
                  onEditingComplete: _submit,
                  onSubmitted: (_) => _submit(),
                  onTapOutside: (_) {
                    _submit();
                    _focus.unfocus();
                  },
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          child: Listener(
            onPointerCancel: (_) => _cancel(),
            child: Tooltip(
              message: VenueLayoutStrings.text(
                context,
                'Double-click to reset',
              ),
              child: GestureDetector(
                onDoubleTap: _enabled && widget.onReset != null ? _reset : null,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 12,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  child: Slider(
                    key: ValueKey(
                      widget.label == 'Font size'
                          ? 'font-size-slider'
                          : 'number-slider:${widget.label}',
                    ),
                    min: math.max(widget.min, _min),
                    max: _max,
                    value: widget.value,
                    label: _display(widget.value),
                    semanticFormatterCallback: (value) =>
                        '${VenueLayoutStrings.text(context, widget.label)} ${_display(value)}',
                    onChangeStart: _enabled ? _start : null,
                    onChanged: _enabled ? _change : null,
                    onChangeEnd: _enabled ? _finish : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
