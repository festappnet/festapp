import 'package:flutter/material.dart';
import 'package:fstapp/components/forms/db_forms.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'form_public_link.dart';
import '../form_strings.dart';
import '../models/form_model.dart';
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
    if (result is FormModel) {
      await copyFormToOccasion(context, result,
          occasionLink: occasionLink, onFormCreated: onFormCreated);
    } else if (result == 'CREATE_NEW') {
      await showCreateFormDialog(context,
          occasionLink: occasionLink, onFormCreated: onFormCreated);
    }
  }

  static Future<void> copyFormToOccasion(BuildContext context, FormModel form,
      {required String occasionLink,
      required VoidCallback onFormCreated}) async {
    try {
      await DbForms.duplicateFormToOccasion(
          sourceFormId: form.id!, targetOccasionLink: occasionLink);
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
    String link = "${FormStrings.defaultFormTitle}${DateTime.now().year}";

    final titleController = TextEditingController(text: title);
    final linkController = TextEditingController(text: link);
    final linkNotifier = ValueNotifier<String>(link);

    bool isLinkManuallyChanged = false;
    String? linkError;
    bool isCreating = false;

    void validateLink(String? value) {
      if (value == null || value.isEmpty) {
        linkError = FormStrings.validationLinkRequired;
      } else if (!Utilities.isValidUrl(value)) {
        linkError = FormStrings.validationLinkInvalidChars;
      } else {
        linkError = null;
      }
    }

    void updateLink() {
      var processedTitle = Utilities.removeDiacritics(titleController.text);
      if (processedTitle.isEmpty) return;

      var firstWord = processedTitle.split(' ').first.toLowerCase();
      var currentYear = DateTime.now().year;

      link = "$firstWord$currentYear";
      linkController.text = link;
      linkNotifier.value = link;
    }

    titleController.addListener(() {
      if (!isLinkManuallyChanged) {
        updateLink();
      }
    });

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

            return AlertDialog(
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
                            isLinkManuallyChanged = true;
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
                          if (formLink.isEmpty)
                            return const SizedBox.shrink();
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
                          link = linkController.text.trim();

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
