import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import '../services_feature.dart';

extension ServicesFeatureSettingsEditor on ServicesFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return StatefulBuilder(builder: (ctx, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        EditorDraftScope.changed(ctx);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            InventoryStrings.featureModeTitle,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          RadioListTile<String>(
            title: Text(InventoryStrings.featureModeStay),
            subtitle: Text(
              InventoryStrings.featureModeStayHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: FeatureConstants.servicesModeStay,
            groupValue: mode,
            onChanged: (value) => setLocal(() {
              mode = FeatureConstants.servicesModeStay;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
          // Independent sub-toggles for the stay mode.
          if (isStayMode)
            Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CheckboxListTile(
                    title: Text(InventoryStrings.featureAllowAccommodation),
                    value: allowAccommodation,
                    onChanged: (value) => setLocal(() {
                      allowAccommodation = value ?? false;
                      // Keep at least one sub-type enabled.
                      if (!allowAccommodation && !allowFood) allowFood = true;
                    }),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    title: Text(InventoryStrings.featureAllowFood),
                    value: allowFood,
                    onChanged: (value) => setLocal(() {
                      allowFood = value ?? false;
                      if (!allowFood && !allowAccommodation) {
                        allowAccommodation = true;
                      }
                    }),
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
          RadioListTile<String>(
            title: Text(InventoryStrings.featureModeCapacityGroups),
            subtitle: Text(
              InventoryStrings.featureModeCapacityGroupsHelp,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            value: FeatureConstants.servicesModeCapacityGroups,
            groupValue: mode,
            onChanged: (value) => setLocal(() {
              mode = FeatureConstants.servicesModeCapacityGroups;
            }),
            dense: true,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      );
    });
  }
}
