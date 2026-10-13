import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/admin_strings.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/components/unit/db_units.dart';
import 'package:fstapp/data_services/rights_service.dart';

class UnitCreationHelper {
  static Future<UnitModel?> createNewUnit(BuildContext context) async {
    final formKey = GlobalKey<FormState>();
    String? title;

    return await showDialog<UnitModel?>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title:
              Text(AdministrationStrings.newUnitButton), // "New organization"
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: InputDecoration(
                    labelText: CommonStrings.title,
                  ),
                  autofocus: true,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return CommonStrings.fieldCannotBeEmpty;
                    }
                    return null;
                  },
                  onSaved: (value) {
                    title = value;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(null);
              },
              child: Text(CommonStrings.storno),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  formKey.currentState!.save();
                  try {
                    final newUnitId =
                        await DbUnits.createUnitAndAssignManager(title!);
                    final currentUser = RightsService.currentUser();

                    final newUnit = UnitModel(
                      id: newUnitId,
                      title: title,
                      // organization: currentUser?.organization,
                      data: {},
                      features: [],
                    );

                    Navigator.of(context).pop(newUnit);
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Error creating unit: $e")),
                    );
                  }
                }
              },
              child: Text(CommonStrings.create),
            ),
          ],
        );
      },
    );
  }
}
