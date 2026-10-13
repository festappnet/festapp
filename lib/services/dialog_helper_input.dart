import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/features/features_strings.dart';
import 'package:fstapp/widgets/drop_file.dart';
import 'package:fstapp/widgets/password_field.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';

class InputDialogs {
  static Future<String?> showInputDialog({
    required BuildContext context,
    String? initialValue,
    required String dialogTitle,
    required String labelText,
  }) async {
    final TextEditingController controller =
        TextEditingController(text: initialValue);

    return await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(dialogTitle),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(labelText: labelText),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(CommonStrings.storno),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context, controller.text.trim());
              },
              child: Text(CommonStrings.save),
            ),
          ],
        );
      },
    );
  }

  static Future<String?> showPasswordInputDialog(
    BuildContext context,
    String titleMessage,
    String hint, [
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  ]) async {
    final TextEditingController messageController = TextEditingController();
    String? result;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titleMessage),
          content: SingleChildScrollView(
            child: Column(
              children: [
                PasswordField(
                  label: hint,
                  controller: messageController,
                  passwordType: AutofillHints.password,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(cancelButtonMessage ?? CommonStrings.storno),
            ),
            ElevatedButton(
              onPressed: () {
                result = messageController.text;
                messageController.clear();
                Navigator.pop(context);
              },
              child: Text(confirmButtonMessage ?? CommonStrings.ok),
            ),
          ],
        );
      },
    );
    return result;
  }

  static Future<ImportDialogChoice?> showImportDialog(
    BuildContext context,
    String titleMessage, {
    required bool showCsvImport,
    required bool showTicketImport,
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) async {
    XFile? filePath;
    ImportDialogChoice? result;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final dropFileWidget = DropFile(
              allowedExtensions: const ['csv'],
              onFilePathChanged: (file) {
                setState(() {
                  filePath = file;
                });
              },
            );

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: Text(titleMessage),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCsvImport) dropFileWidget,
                    if (showCsvImport && showTicketImport) ...[
                      const SizedBox(height: 32),
                    ],
                    if (showTicketImport)
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            result = ImportDialogChoice(fromTickets: true);
                            Navigator.pop(context);
                          },
                          child: Text(FeaturesStrings.importFromTicketsTitle),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    result = null;
                    Navigator.pop(context);
                  },
                  child: Text(cancelButtonMessage ?? CommonStrings.storno),
                ),
                if (showCsvImport)
                  ElevatedButton(
                    onPressed: filePath != null
                        ? () {
                            result = ImportDialogChoice(fromFile: filePath);
                            Navigator.pop(context);
                          }
                        : null,
                    child: Text(FeaturesStrings.labelImportFromCsv),
                  ),
              ],
            );
          },
        );
      },
    );
    return result;
  }

  static Future<XFile?> dropFilesHere(
    BuildContext context,
    String titleMessage,
    String confirmButtonMessage,
    String cancelButtonMessage, {
    Widget? headerContent,
  }) async {
    XFile? filePath;
    final dropFileWidget = DropFile(
      onFilePathChanged: (file) => filePath = file,
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: Text(
            titleMessage,
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (headerContent != null) ...[
                  headerContent,
                  const SizedBox(height: 16),
                ],
                dropFileWidget,
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                filePath = null;
                Navigator.pop(context);
              },
              child: Text(cancelButtonMessage),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: Text(confirmButtonMessage),
            ),
          ],
        );
      },
    );
    return filePath;
  }
}
