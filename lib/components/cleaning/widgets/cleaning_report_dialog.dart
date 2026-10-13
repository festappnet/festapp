import 'package:flutter/material.dart';
import 'package:fstapp/components/cleaning/cleaning_status.dart';
import 'package:fstapp/components/cleaning/cleaning_strings.dart';

/// The chosen problem type + optional note, returned by [CleaningReportDialog].
class CleaningReportOutcome {
  final String problemType;
  final String? note;
  CleaningReportOutcome({required this.problemType, this.note});
}

/// Report dialog: three big colored problem-type buttons (biohazard on the red
/// one) and an optional note field. Picking a type highlights it; "Send"
/// returns the [CleaningReportOutcome].
class CleaningReportDialog extends StatefulWidget {
  final String placeTitle;

  /// Optional "show on map" action (offered from the Cleaning page tiles, not
  /// from the map popup itself). Closes the dialog, then runs the callback.
  final VoidCallback? onShowOnMap;

  const CleaningReportDialog({
    required this.placeTitle,
    this.onShowOnMap,
    super.key,
  });

  @override
  State<CleaningReportDialog> createState() => _CleaningReportDialogState();
}

class _CleaningReportDialogState extends State<CleaningReportDialog> {
  String? _selectedType;
  final _noteController = TextEditingController();

  // Problem types offered to the reporter — keep in sync with the problem_type
  // list in report_cleaning_issue.sql and the cleaning_reports CHECK.
  static const _types = [
    CleaningStatusHelper.codePaper,
    CleaningStatusHelper.codeHygiene,
    CleaningStatusHelper.codeContamination,
  ];

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(CleaningStrings.reportDialogTitle(widget.placeTitle)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final type in _types) ...[
              _buildTypeButton(type),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 4),
            TextField(
              controller: _noteController,
              maxLines: 2,
              maxLength: 2000,
              decoration: InputDecoration(
                hintText: CleaningStrings.noteHint,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.onShowOnMap != null)
          TextButton.icon(
            icon: const Icon(Icons.map_outlined),
            onPressed: () {
              Navigator.of(context).pop();
              widget.onShowOnMap!();
            },
            label: Text(CleaningStrings.showOnMap),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(CleaningStrings.cancel),
        ),
        FilledButton(
          onPressed: _selectedType == null
              ? null
              : () {
                  final note = _noteController.text.trim();
                  Navigator.of(context).pop(CleaningReportOutcome(
                    problemType: _selectedType!,
                    note: note.isEmpty ? null : note,
                  ));
                },
          child: Text(CleaningStrings.send),
        ),
      ],
    );
  }

  Widget _buildTypeButton(String type) {
    final color = CleaningStatusHelper.colorForType(type);
    final selected = _selectedType == type;
    final biohazard = type == CleaningStatusHelper.codeContamination;
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _selectedType = type),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color, width: 2),
            ),
            child: Row(
              children: [
                if (biohazard)
                  const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Text('☣️', style: TextStyle(fontSize: 20)),
                  ),
                Expanded(
                  child: Text(
                    CleaningStrings.problemLabel(type),
                    style: TextStyle(
                      color: selected ? Colors.white : null,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
