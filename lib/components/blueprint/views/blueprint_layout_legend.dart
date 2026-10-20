import 'package:flutter/material.dart';
import '../blueprint_seat_state.dart';
import '../blueprint_strings.dart';

/// Visible map key: matching markers plus plain-language meanings and counts.
class BlueprintLayoutLegend extends StatelessWidget {
  const BlueprintLayoutLegend({super.key, required this.states});
  final Iterable<BlueprintSeatState> states;

  Color _fill(BlueprintSeatState state) {
    final rgba = blueprintSeatStateFills[state]!;
    return Color.alphaBlend(
        Color(int.parse('${rgba.substring(7, 9)}${rgba.substring(1, 7)}',
            radix: 16)),
        Colors.white);
  }

  Widget _entry(BuildContext context, BlueprintSeatState state, int count,
      {bool selection = false}) {
    final label = selection
        ? BlueprintStrings.legendSelected
        : BlueprintStrings.seatState(state.name);
    final crossed = state == BlueprintSeatState.ordered;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ExcludeSemantics(
            child: Container(
          width: 20,
          height: 20,
          margin: const EdgeInsets.only(top: 2, right: 10),
          decoration: BoxDecoration(
              color: _fill(state),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant)),
          child: selection
              ? const Icon(Icons.check, size: 16, color: Colors.white)
              : crossed
                  ? Icon(Icons.close,
                      size: 16,
                      color: state == BlueprintSeatState.blocked
                          ? Colors.white
                          : const Color(0xff444444))
                  : null,
        )),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(selection ? label : '$label ($count)',
              style: Theme.of(context).textTheme.labelLarge),
          Text(
              BlueprintStrings.seatStateDescription(
                  selection ? 'selection' : state.name),
              style: Theme.of(context).textTheme.bodySmall),
        ])),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final counts = <BlueprintSeatState, int>{};
    for (final state in states) {
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return Padding(
      key: const ValueKey('blueprint-seat-legend'),
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(BlueprintStrings.helpSeatStates,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 6),
        for (final state in [
          BlueprintSeatState.available,
          BlueprintSeatState.ordered,
          BlueprintSeatState.used,
          BlueprintSeatState.selected,
          BlueprintSeatState.blocked,
          if ((counts[BlueprintSeatState.empty] ?? 0) > 0)
            BlueprintSeatState.empty
        ])
          _entry(context, state, counts[state] ?? 0),
        _entry(context, BlueprintSeatState.selectedByMe,
            counts[BlueprintSeatState.selectedByMe] ?? 0,
            selection: true),
      ]),
    );
  }
}
