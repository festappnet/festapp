import 'package:fstapp/components/_shared/editor_draft_scope.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/features/features_strings.dart';
import '../companion_feature.dart';

extension CompanionsFeatureSettingsEditor on CompanionsFeature {
  Widget buildSettingsEditor(BuildContext context) {
    return StatefulBuilder(builder: (context, updateLocal) {
      void setLocal(VoidCallback change) {
        updateLocal(change);
        EditorDraftScope.changed(context);
      }

      return Column(
        children: [
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(FeaturesStrings.companionsAllowUserCreate),
            value: allowUserCreate,
            onChanged: (value) =>
                setLocal(() => allowUserCreate = value ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(FeaturesStrings.companionsAllowAdminAssign),
            value: allowAdminAssign,
            onChanged: (value) =>
                setLocal(() => allowAdminAssign = value ?? false),
          ),
          TextFormField(
            initialValue: companionsMax?.toString(),
            decoration: InputDecoration(labelText: CommonStrings.max),
            keyboardType: TextInputType.number,
            validator: (val) {
              final n = int.tryParse(val ?? '');
              if (n == null || n < 1) {
                return FeaturesStrings.enterNumberGreaterThanZero;
              }
              return null;
            },
            onSaved: (val) =>
                companionsMax = int.tryParse(val ?? '') ?? companionsMax,
          ),
        ],
      );
    });
  }
}
