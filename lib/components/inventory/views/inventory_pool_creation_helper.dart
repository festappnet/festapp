import 'package:flutter/material.dart';
import 'package:fstapp/components/inventory/models/inventory_pool_bundle.dart';
import 'package:fstapp/components/inventory/db_inventory_pools.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/toast_helper.dart';

import 'inventory_strings.dart';
import '../models/inventory_pool_model.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class InventoryPoolCreationHelper {
  static Future<void> showCreatePoolDialog({
    required BuildContext context,
    required int occasionId,
    required VoidCallback onPoolCreated,
  }) async {
    final formKey = GlobalKey<FormState>();
    final titleController = TextEditingController(
        text: InventoryStrings.creationDialogNewPoolTitle);
    bool isCreating = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(InventoryStrings.creationDialogTitle),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: InventoryStrings.poolTitleLabel,
                          border: const OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return InventoryStrings.validationTitleEmpty;
                          }
                          return null;
                        },
                        autofocus: true,
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: isCreating
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(CommonStrings.storno),
                ),
                ElevatedButton(
                  onPressed: isCreating
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) {
                            return;
                          }

                          setState(() {
                            isCreating = true;
                          });

                          final newPool = InventoryPoolModel(
                            id: null,
                            title: titleController.text.trim(),
                            occasionId: occasionId,
                            type: allowedInventoryPoolTypes().first,
                          );

                          final bundle = InventoryPoolBundle(
                            pool: newPool,
                            resources: [],
                            contexts: [],
                          );

                          final result = await ExceptionHandler.guard(
                            dialogContext,
                            futureFunction: () =>
                                DbInventoryPools.updateInventoryPoolBundle(
                                    bundle),
                            defaultErrorMessage:
                                InventoryStrings.creationDialogErrorDefault,
                          );

                          // The guard returns null if an error was handled.
                          // We only proceed if the result is not null (i.e., the call succeeded).
                          if (result != null) {
                            if (dialogContext.mounted) {
                              await ToastHelper.Show(dialogContext,
                                  InventoryStrings.creationDialogSuccess,
                                  severity: ToastSeverity.Ok);
                              onPoolCreated();
                              Navigator.of(dialogContext).pop();
                            }
                          }

                          // This replaces the 'finally' block.
                          if (dialogContext.mounted) {
                            setState(() {
                              isCreating = false;
                            });
                          }
                        },
                  child: isCreating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(CommonStrings.create),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
