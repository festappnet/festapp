import 'package:fstapp/widgets/app_dialog.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'form_public_link.dart';
import '../form_strings.dart';
import '../models/form_bundle.dart';
import 'create_or_copy_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class FormCreationHelper {
  static Future<void> showCreateOrCopyFormDialog(BuildContext context,
      {required String occasionLink,
      required VoidCallback onFormCreated}) async {
    final forms = await DbForms.getAllFormsForOccasionOrUnit();
    if (!context.mounted) return;
    final result = await showDialog<dynamic>(
        context: context,
        builder: (_) => CreateOrCopyFormDialog(existingForms: forms));
    if (!context.mounted || result == null) return;
    if (result is FormBundle) {
      await copyFormToOccasion(context, result,
          occasionLink: occasionLink, onFormCreated: onFormCreated);
    } else if (result == 'CREATE_NEW') {
      await showCreateFormDialog(context,
          occasionLink: occasionLink, onFormCreated: onFormCreated);
    }
  }

  static Future<void> copyFormToOccasion(BuildContext context, FormBundle form,
      {required String occasionLink,
      required VoidCallback onFormCreated}) async {
    try {
      await DbForms.duplicateFormToOccasion(
          sourceFormId: form.definition.id!, targetOccasionLink: occasionLink);
      if (!context.mounted) return;
      ToastHelper.Show(context, FormStrings.duplicateSuccess,
          severity: ToastSeverity.Ok);
      onFormCreated();
    } catch (error) {
      if (!context.mounted) return;
      ToastHelper.Show(
          context, error.toString().replaceFirst('Exception: ', ''),
          severity: ToastSeverity.NotOk);
    }
  }

  static Future<void> showCreateFormDialog(
    BuildContext context, {
    required String occasionLink,
    required Function onFormCreated,
  }) async {
    final formKey = GlobalKey<FormState>();

    String title = FormStrings.defaultFormTitle;
    String link = '';

    final titleController = TextEditingController(text: title);
    final linkController = TextEditingController(text: link);
    final linkNotifier = ValueNotifier<String>(link);

    String? linkError;
    bool isCreating = false;

    void validateLink(String? value) {
      if (!isValidPublicSlug(value ?? '', allowEmpty: true)) {
        linkError = FormStrings.validationLinkInvalidChars;
      } else {
        linkError = null;
      }
    }

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            bool isFormValid() {
              validateLink(linkController.text);
              return titleController.text.trim().isNotEmpty &&
                  linkError == null;
            }

            return AppAlertDialog(
              onClose: () => Navigator.of(context).pop(),
              title: Text(FormStrings.createNewForm),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      TextFormField(
                        controller: titleController,
                        decoration: InputDecoration(
                          labelText: FormStrings.labelFormTitle,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (value) {
                          setState(() {
                            title = value;
                          });
                        },
                        autofocus: true,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: linkController,
                        decoration: InputDecoration(
                          labelText: FormStrings.labelFormLink,
                          border: const OutlineInputBorder(),
                          errorText: linkError,
                        ),
                        onChanged: (value) {
                          setState(() {
                            link = value;
                            linkNotifier.value = value;
                            validateLink(value);
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      ValueListenableBuilder<String>(
                        valueListenable: linkNotifier,
                        builder: (context, formLink, child) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8.0),
                            child: FormPublicLink(link: formLink),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(CommonStrings.storno),
                ),
                ElevatedButton(
                  onPressed: isFormValid() && !isCreating
                      ? () async {
                          setState(() {
                            isCreating = true;
                            linkError = null;
                          });

                          title = titleController.text.trim();
                          link = linkController.text;

                          try {
                            await DbForms.createNewForm(
                              title: title,
                              link: link,
                              occasionLink: occasionLink,
                            );

                            if (!context.mounted) return;
                            ToastHelper.Show(
                                context, FormStrings.formCreatedSuccess,
                                severity: ToastSeverity.Ok);
                            onFormCreated();
                            Navigator.of(context).pop();
                          } catch (e) {
                            if (!context.mounted) return;
                            setState(() {
                              linkError =
                                  e.toString().replaceFirst("Exception: ", "");
                            });
                          } finally {
                            if (context.mounted) {
                              setState(() {
                                isCreating = false;
                              });
                            }
                          }
                        }
                      : null,
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
