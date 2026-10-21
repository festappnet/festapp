import 'package:flutter/material.dart';

/// Shared B/I/U control. Hosts own the document and available font faces.
class EditorTextStyleControl extends StatelessWidget {
  const EditorTextStyleControl({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.translate,
    this.available = const {'bold', 'italic', 'underline'},
    this.showUnderline = true,
  });
  final Set<String> selected, available;
  final bool showUnderline;
  final ValueChanged<Set<String>>? onChanged;
  final String Function(String) translate;
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    multiSelectionEnabled: true,
    emptySelectionAllowed: true,
    showSelectedIcon: false,
    segments: [
      for (final entry in const {
        'bold': (Icons.format_bold, 'Bold'),
        'italic': (Icons.format_italic, 'Italic'),
        'underline': (Icons.format_underlined, 'Underline'),
      }.entries)
        if (entry.key != 'underline' || showUnderline)
          ButtonSegment(
            value: entry.key,
            icon: Icon(entry.value.$1),
            tooltip: translate(entry.value.$2),
            enabled: available.contains(entry.key),
          ),
    ],
    selected: selected,
    onSelectionChanged: onChanged,
  );
}

class EditorTextAlignmentControl extends StatelessWidget {
  const EditorTextAlignmentControl({
    super.key,
    required this.value,
    required this.onChanged,
    required this.translate,
  });
  final String value;
  final ValueChanged<String>? onChanged;
  final String Function(String) translate;
  @override
  Widget build(BuildContext context) => SegmentedButton<String>(
    showSelectedIcon: false,
    segments: [
      for (final entry in const {
        'left': (Icons.format_align_left, 'Left'),
        'center': (Icons.format_align_center, 'Center'),
        'right': (Icons.format_align_right, 'Right'),
      }.entries)
        ButtonSegment(
          value: entry.key,
          icon: Icon(entry.value.$1),
          tooltip: translate(entry.value.$2),
        ),
    ],
    selected: {value},
    onSelectionChanged: onChanged == null
        ? null
        : (values) => onChanged!(values.single),
  );
}
