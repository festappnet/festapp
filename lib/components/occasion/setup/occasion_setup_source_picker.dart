import 'package:flutter/material.dart';
import 'occasion_setup_strings.dart';

class OccasionSetupSourcePicker extends StatelessWidget {
  const OccasionSetupSourcePicker(
      {super.key,
      required this.sources,
      required this.selectedId,
      required this.label,
      required this.onChanged,
      this.unavailableLabel});
  final List<Map<String, dynamic>> sources;
  final int? selectedId;
  final String Function(Map<String, dynamic>) label;
  final ValueChanged<int?> onChanged;
  final String? unavailableLabel;

  @override
  Widget build(BuildContext context) {
    final labels = {
      for (final source in sources)
        (source['occasion'] as Map)['id'] as int: label(source)
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<int>(
        key: ValueKey(selectedId),
        initialValue: selectedId ?? 0,
        isExpanded: true,
        decoration: InputDecoration(
            labelText: OccasionSetupStrings.copy('source'),
            border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem(
              value: 0, child: Text(OccasionSetupStrings.copy('fromScratch'))),
          for (final source in sources)
            DropdownMenuItem(
              value: (source['occasion'] as Map)['id'] as int,
              child: Text(
                  labels.values.where((text) => text == label(source)).length >
                          1
                      ? '${label(source)} · ${(source['occasion'] as Map)['link'] ?? (source['occasion'] as Map)['id']}'
                      : label(source),
                  overflow: TextOverflow.ellipsis),
            ),
          if (selectedId != null && !labels.containsKey(selectedId))
            DropdownMenuItem(
                value: selectedId,
                child: Text(unavailableLabel ?? '#$selectedId')),
        ],
        onChanged: (id) => onChanged(id == 0 ? null : id),
      ),
    );
  }
}
