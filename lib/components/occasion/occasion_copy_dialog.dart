import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/unit_strings.dart';
import 'package:fstapp/widgets/app_dialog.dart';

Future<UnitModel?> showOccasionCopyTargetDialog(
    BuildContext context, List<UnitModel> destinations,
    {int? sourceUnitId, String? hint}) async {
  if (destinations.isEmpty) return null;
  final units = {for (final unit in destinations) unit.id!: unit};
  var selected =
      units.containsKey(sourceUnitId) ? sourceUnitId! : units.keys.first;
  return showDialog<UnitModel>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AppAlertDialog(
                  onClose: () => Navigator.of(dialogContext).pop(),
                  title: Text(UnitStrings.createCopy),
                  content: SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(UnitStrings.createCopyConfirm),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<int>(
                                initialValue: selected,
                                isExpanded: true,
                                decoration: InputDecoration(
                                    labelText: UnitStrings.copyTargetUnit),
                                items: units.values
                                    .map((unit) => DropdownMenuItem(
                                        value: unit.id!,
                                        child: Text(
                                            unit.title ?? unit.id.toString())))
                                    .toList(),
                                onChanged: (id) {
                                  if (id != null)
                                    setDialogState(() => selected = id);
                                }),
                            if (hint != null || selected != sourceUnitId) ...[
                              const SizedBox(height: 12),
                              Text(hint ?? UnitStrings.copyTargetHint)
                            ],
                          ]))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: Text(CommonStrings.storno)),
                    FilledButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(units[selected]),
                        child: Text(UnitStrings.createCopy))
                  ])));
}
