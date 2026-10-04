import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/views/inventory_strings.dart';
import 'feature.dart';
import 'feature_constants.dart';

/// Feature backing the "Pobyt (kapacitní skupiny)" / Inventory module.
///
/// Lets an occasion decide which kinds of capacity groups are allowed. The two
/// top-level modes are mutually exclusive:
///   * [FeatureConstants.servicesModeStay] – accommodation and/or food pools.
///   * [FeatureConstants.servicesModeCapacityGroups] – generic capacity groups
///     only (the `other` pool type).
///
/// Within stay mode, accommodation and food are independently toggleable.
class ServicesFeature extends Feature {
  String mode;
  bool allowAccommodation;
  bool allowFood;

  ServicesFeature({
    required super.code,
    super.isEnabled,
    super.title,
    super.description,
    String? mode,
    bool? allowAccommodation,
    bool? allowFood,
  })  : mode = mode ?? FeatureConstants.servicesModeStay,
        allowAccommodation = allowAccommodation ?? true,
        allowFood = allowFood ?? true;

  bool get isCapacityGroupsMode =>
      mode == FeatureConstants.servicesModeCapacityGroups;
  bool get isStayMode => !isCapacityGroupsMode;

  /// Accommodation is offered only in stay mode when its sub-toggle is on.
  bool get allowsAccommodation => isStayMode && allowAccommodation;

  /// Food is offered only in stay mode when its sub-toggle is on.
  bool get allowsFood => isStayMode && allowFood;

  /// Generic capacity groups are offered only in capacity-groups mode.
  bool get allowsCapacityGroups => isCapacityGroupsMode;

  factory ServicesFeature.fromJson(Map<String, dynamic> json) {
    return ServicesFeature(
      code: json[FeatureConstants.metaCode],
      isEnabled: json[FeatureConstants.metaIsEnabled] ?? false,
      mode: json[FeatureConstants.servicesMode],
      allowAccommodation: json[FeatureConstants.servicesAllowAccommodation],
      allowFood: json[FeatureConstants.servicesAllowFood],
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{
      FeatureConstants.metaCode: code,
      FeatureConstants.metaIsEnabled: isEnabled,
      FeatureConstants.servicesMode: mode,
    };
    if (isStayMode) {
      data[FeatureConstants.servicesAllowAccommodation] = allowAccommodation;
      data[FeatureConstants.servicesAllowFood] = allowFood;
    }
    return data;
  }

  @override
  Widget buildFormField(BuildContext context) {
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
