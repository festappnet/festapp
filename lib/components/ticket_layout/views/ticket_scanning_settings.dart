import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/components/features/ticket_feature.dart';

/// Optional admission-control settings, independent of the printed ticket.
class TicketScanningSettings extends StatefulWidget {
  final TicketFeature feature;
  final bool readOnly;
  final VoidCallback? onChanged;

  const TicketScanningSettings(
      {super.key,
      required this.feature,
      this.readOnly = false,
      this.onChanged});

  @override
  State<TicketScanningSettings> createState() => _TicketScanningSettingsState();
}

class _TicketScanningSettingsState extends State<TicketScanningSettings> {
  void _change(VoidCallback update) {
    setState(update);
    EditorDraftScope.changed(context);
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        CheckboxListTile(
            value: widget.feature.canScanManually ?? false,
            title: Text(FeaturesStrings.enableManualTicketScan),
            subtitle: Text(FeaturesStrings.enableManualTicketScanDescription),
            onChanged: widget.readOnly
                ? null
                : (value) =>
                    _change(() => widget.feature.canScanManually = value)),
        CheckboxListTile(
            value: widget.feature.showHiddenNote ?? false,
            title: Text(FeaturesStrings.labelShowHiddenNote),
            subtitle: Text(FeaturesStrings.descriptionShowHiddenNote),
            onChanged: widget.readOnly
                ? null
                : (value) =>
                    _change(() => widget.feature.showHiddenNote = value)),
      ]);
}
