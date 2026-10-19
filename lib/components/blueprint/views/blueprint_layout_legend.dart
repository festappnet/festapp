import 'package:flutter/material.dart';
import '../blueprint_seat_state.dart';
import '../blueprint_strings.dart';

/// Status labels and counts remain legible without relying on chair colors.
class BlueprintLayoutLegend extends StatelessWidget {
  const BlueprintLayoutLegend({super.key, required this.states});
  final Iterable<BlueprintSeatState> states;

  @override
  Widget build(BuildContext context) {
    final counts = <BlueprintSeatState, int>{};
    for (final state in states) {
      counts[state] = (counts[state] ?? 0) + 1;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Wrap(spacing: 12, runSpacing: 4, children: [
        for (final state in BlueprintSeatState.values)
          Text('${BlueprintStrings.seatState(state.name)}: ${counts[state] ?? 0}',
              style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}
