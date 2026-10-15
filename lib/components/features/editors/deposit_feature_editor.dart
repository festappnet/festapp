import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/occasion_settings/occasion_settings_strings.dart';
import '../deposit_feature.dart';

extension DepositFeatureSettingsEditor on DepositFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return StatefulBuilder(builder: (ctx, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        EditorDraftScope.changed(ctx);
      }

      final daysController = TextEditingController(
        text: depositDeadlineDays?.toString() ?? '7',
      );
      final metaSurchargeController = TextEditingController(
        text: metaSurchargeDescription ?? '',
      );

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode toggle: real vs virtual (mutually exclusive)
          Text(
            OccasionSettingsStrings.depositModeTitle,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          RadioListTile<String>(
            title: Text(OccasionSettingsStrings.depositModeReal),
            subtitle: Text(
              OccasionSettingsStrings.depositModeRealHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: FeatureConstants.depositModeReal,
            groupValue: mode,
            onChanged: (value) => setLocal(() {
              mode = FeatureConstants.depositModeReal;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          RadioListTile<String>(
            title: Text(OccasionSettingsStrings.depositModeVirtual),
            subtitle: Text(
              OccasionSettingsStrings.depositModeVirtualHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: FeatureConstants.depositModeVirtual,
            groupValue: mode,
            onChanged: (value) => setLocal(() {
              mode = FeatureConstants.depositModeVirtual;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          const SizedBox(height: 8),
          if (isRealMode) ...[
            Text(
              OccasionSettingsStrings.depositDeadline,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            RadioListTile<String>(
              title: Text(OccasionSettingsStrings.depositDeadlineDaysBefore),
              value: "days_before",
              groupValue:
                  depositDeadline == "on_site" ? "on_site" : "days_before",
              onChanged: (value) {
                setLocal(() {
                  if (depositDeadlineDays == null) {
                    depositDeadlineDays = 7;
                    daysController.text = '7';
                  }
                  depositDeadline = null;
                });
              },
            ),
            if (depositDeadline != "on_site")
              Padding(
                padding: const EdgeInsets.only(left: 32.0, right: 16.0),
                child: TextFormField(
                  controller: daysController,
                  decoration: InputDecoration(
                    labelText: OccasionSettingsStrings.numberOfDays,
                    hintText: '7',
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (val) {
                    if (depositDeadline == "on_site") return null;
                    if (val == null || val.isEmpty) return null;
                    final intVal = int.tryParse(val);
                    if (intVal == null || intVal < 0) {
                      return OccasionSettingsStrings.invalidNumber;
                    }
                    return null;
                  },
                  onChanged: (val) {
                    depositDeadlineDays = int.tryParse(val);
                  },
                ),
              ),
            RadioListTile<String>(
              title: Text(OccasionSettingsStrings.depositDeadlineOnSite),
              value: "on_site",
              groupValue:
                  depositDeadline == "on_site" ? "on_site" : "days_before",
              onChanged: (value) {
                setLocal(() {
                  depositDeadline = "on_site";
                  depositDeadlineDays = null;
                });
              },
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: TextFormField(
                controller: metaSurchargeController,
                decoration: InputDecoration(
                  labelText: OccasionSettingsStrings.metaSurchargeDescription,
                  helperText:
                      OccasionSettingsStrings.metaSurchargeDescriptionHelp,
                  helperMaxLines: 3,
                  border: const OutlineInputBorder(),
                ),
                minLines: 1,
                maxLines: 3,
                onChanged: (val) {
                  metaSurchargeDescription = val.trim().isEmpty ? null : val;
                },
              ),
            ),
          ],
        ],
      );
    });
  }
}
