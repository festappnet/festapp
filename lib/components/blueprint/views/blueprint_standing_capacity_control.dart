import 'package:flutter/material.dart';
import 'package:venue_seat_picker/editor_ui.dart';
import '../blueprint_layout_controller.dart';
import '../blueprint_strings.dart';

class BlueprintStandingCapacityControl extends StatefulWidget {
  const BlueprintStandingCapacityControl(
      {super.key,
      required this.controller,
      required this.nodeId,
      required this.enabled});
  final BlueprintLayoutController controller;
  final String nodeId;
  final bool enabled;
  @override
  State<BlueprintStandingCapacityControl> createState() => _CapacityState();
}

class _CapacityState extends State<BlueprintStandingCapacityControl> {
  late final text = TextEditingController(text: value.toString());
  final focus = FocusNode();
  String? error;
  late int lastValue = value;
  int get value => widget.controller.areaCapacity(widget.nodeId);
  bool get dirty => int.tryParse(text.text) != value;
  @override
  void initState() {
    super.initState();
    lastValue = value;
    focus.addListener(_focusChanged);
  }

  void _focusChanged() {
    if (!focus.hasFocus && dirty) commit();
  }

  @override
  void didUpdateWidget(covariant BlueprintStandingCapacityControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (lastValue != value || oldWidget.nodeId != widget.nodeId) {
      lastValue = value;
      text.text = value.toString();
      error = null;
    }
  }

  void commit() {
    final next = int.tryParse(text.text);
    if (!widget.enabled) return;
    if (next == null || next < 0 || next > 1000000) {
      setState(() => error = BlueprintStrings.invalidStandingCapacity);
      return;
    }
    if (next == value) return;
    try {
      widget.controller.setAreaCapacity(widget.nodeId, next);
      setState(() => error = null);
    } catch (_) {
      setState(() => error = BlueprintStrings.invalidStandingCapacity);
    }
  }

  @override
  void dispose() {
    focus.removeListener(_focusChanged);
    focus.dispose();
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => EditorFieldHistory(
        hasUncommittedChanges: () => dirty,
        onUndo: widget.controller.layout.undo,
        onRedo: widget.controller.layout.redo,
        child: EditorNumberScroll(
          enabled: widget.enabled,
          step: 1,
          min: 0,
          max: 1000000,
          onChanged: commit,
          child: TextField(
            key: const ValueKey('standing-capacity-field'),
            controller: text,
            focusNode: focus,
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
                labelText: BlueprintStrings.standingSalesLimit,
                errorText: error,
                helperText:
                    '${BlueprintStrings.capacitySaveHint} ${BlueprintStrings.standingSupplyHint}',
                helperMaxLines: 5,
                border: const OutlineInputBorder()),
            onEditingComplete: commit,
            onSubmitted: (_) => commit(),
          ),
        ),
      );
}
