import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/services/import_file.dart';
import 'package:material_ui/material_ui.dart';
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
        return AppAlertDialog(
          onClose: () => Navigator.pop(context),
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
        return AppAlertDialog(
          onClose: () => Navigator.pop(context),
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
    ImportFile? filePath;
    ImportDialogChoice? result;

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            final dropFileWidget = DropFile(
              allowedExtensions: const ['csv'],
              onFilePathChanged: (file) async {
                setState(() { filePath = file; });
                await file.retain();
              },
            );

            return AppAlertDialog(
              onClose: () {
                result = null;
                Navigator.pop(context);
              },
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
    await result?.fromFile?.retain();
    return result;
  }

  static Future<ImportFile?> dropFilesHere(
    BuildContext context,
    String titleMessage,
    String confirmButtonMessage,
    String cancelButtonMessage, {
    Widget? headerContent,
    List<String>? allowedExtensions,
    bool singleFileOnly = false,
    VoidCallback? onInvalidDrop,
  }) async {
    ImportFile? filePath;
    final dropFileWidget = DropFile(
      allowedExtensions: allowedExtensions,
      singleFileOnly: singleFileOnly,
      onInvalidDrop: onInvalidDrop,
      onFilePathChanged: (file) async {
        filePath = file;
        await file.retain();
      },
    );

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AppAlertDialog(
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
    await filePath?.retain();
    return filePath;
  }
}
