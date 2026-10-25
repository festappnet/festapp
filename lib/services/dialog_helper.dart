import 'package:fstapp/services/import_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/app_config.dart';
import 'package:fstapp/components/app_management/language_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/dialog_helper_confirmation.dart';
import 'package:fstapp/services/dialog_helper_input.dart';
import 'package:fstapp/services/dialog_helper_progress.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/theme_config.dart';
import 'package:fstapp/components/dialogs/responsive_search_dialog.dart';
import 'package:fstapp/data_services/data_extensions.dart';
import 'package:fstapp/widgets/app_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

export 'package:fstapp/services/dialog_helper_confirmation.dart';
export 'package:fstapp/services/dialog_helper_input.dart';
export 'package:fstapp/services/dialog_helper_progress.dart';

class ImportDialogChoice {
  final bool fromTickets;
  final ImportFile? fromFile;
  ImportDialogChoice({this.fromTickets = false, this.fromFile});
}

class DialogHelper {
  static Widget createDialogAction(String text, void Function() onPressed) {
    return TextButton(onPressed: onPressed, child: Text(text));
  }

  static Future<ImportDialogChoice?> showImportDialog(
    BuildContext context,
    String titleMessage, {
    required bool showCsvImport,
    required bool showTicketImport,
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) => InputDialogs.showImportDialog(
    context,
    titleMessage,
    showCsvImport: showCsvImport,
    showTicketImport: showTicketImport,
    confirmButtonMessage: confirmButtonMessage,
    cancelButtonMessage: cancelButtonMessage,
  );

  static Future<void> showInformationDialog(
    BuildContext context,
    String titleMessage,
    String textMessage, [
    String? buttonMessage,
  ]) => ConfirmationDialogs.showInformationDialog(
    context,
    titleMessage,
    textMessage,
    buttonMessage,
  );

  static Future<bool> showScanTicketCode(
    BuildContext context,
    String titleMessage,
    String textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) => ConfirmationDialogs.showScanTicketCode(
    context,
    titleMessage,
    textMessage,
    confirmButtonMessage: confirmButtonMessage,
    cancelButtonMessage: cancelButtonMessage,
  );

  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String titleMessage,
    String textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) => ConfirmationDialogs.showConfirmationDialog(
    context,
    titleMessage,
    textMessage,
    confirmButtonMessage: confirmButtonMessage,
    cancelButtonMessage: cancelButtonMessage,
  );

  static Future<bool> showConfirmationDialogRichText(
    BuildContext context,
    String titleMessage,
    Text textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) => ConfirmationDialogs.showConfirmationDialogRichText(
    context,
    titleMessage,
    textMessage,
    confirmButtonMessage: confirmButtonMessage,
    cancelButtonMessage: cancelButtonMessage,
  );

  static Future<bool> showConfirmationDialogRich({
    required BuildContext context,
    required String title,
    required Widget content,
    String? confirmButtonText,
    String? cancelButtonText,
  }) => ConfirmationDialogs.showConfirmationDialogRich(
    context: context,
    title: title,
    content: content,
    confirmButtonText: confirmButtonText,
    cancelButtonText: cancelButtonText,
  );

  static Future<bool> showNotificationPermissionDialog(BuildContext context) =>
      ConfirmationDialogs.showNotificationPermissionDialog(context);

  static Future<String?> showPasswordInputDialog(
    BuildContext context,
    String titleMessage,
    String hint, [
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  ]) => InputDialogs.showPasswordInputDialog(
    context,
    titleMessage,
    hint,
    confirmButtonMessage,
    cancelButtonMessage,
  );

  static Future<ImportFile?> dropFilesHere(
    BuildContext context,
    String titleMessage,
    String confirmButtonMessage,
    String cancelButtonMessage, {
    Widget? headerContent,
    List<String>? allowedExtensions,
  }) => InputDialogs.dropFilesHere(
    context,
    titleMessage,
    confirmButtonMessage,
    cancelButtonMessage,
    headerContent: headerContent,
    allowedExtensions: allowedExtensions,
  );

  static Future<String?> showInputDialog({
    required BuildContext context,
    String? initialValue,
    required String dialogTitle,
    required String labelText,
  }) => InputDialogs.showInputDialog(
    context: context,
    initialValue: initialValue,
    dialogTitle: dialogTitle,
    labelText: labelText,
  );

  static Future<bool> showProgressDialogAsync(
    BuildContext context,
    String title,
    int total, {
    List<Future<void> Function()>? futures,
    Duration? delay,
    bool isBasic = false,
  }) => ProgressDialogs.showProgressDialogAsync(
    context,
    title,
    total,
    futures: futures,
    delay: delay,
    isBasic: isBasic,
  );

  static Future<T?> showFutureProgressDialog<T>({
    required BuildContext context,
    required String title,
    required Future<T> Function() futureCallback,
  }) => ProgressDialogs.showFutureProgressDialog<T>(
    context: context,
    title: title,
    futureCallback: futureCallback,
  );

  static Future<void> chooseUser(
    BuildContext context,
    void Function(UserInfoModel) onPressedAction,
    List<UserInfoModel> allUsers,
    String setText, {
    bool useRootNavigator = true,
    String? emptyMessage,
    String? description,
  }) async {
    await showDialog(
      useRootNavigator: useRootNavigator,
      context: context,
      builder: (context) => ResponsiveSearchDialog<UserInfoModel>(
        items: allUsers,
        description: description,
        emptyState: emptyMessage == null
            ? null
            : Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(emptyMessage, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(CommonStrings.back),
                      ),
                    ],
                  ),
                ),
              ),
        searchLabel: CommonStrings.searchParticipants,
        filter: (person, query) {
          final q = query.toLowerCase().withoutDiacriticalMarks;
          return (person.name?.toLowerCase().withoutDiacriticalMarks.contains(
                    q,
                  ) ??
                  false) ||
              (person.surname?.toLowerCase().withoutDiacriticalMarks.contains(
                    q,
                  ) ??
                  false) ||
              (person.email?.toLowerCase().contains(q) ?? false);
        },
        itemBuilder: (person) => ListTile(
          title: Text(person.name!),
          subtitle: Text(person.surname ?? ""),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  onPressedAction(person);
                },
                child: Text(setText),
              ),
              Text(person.email ?? ""),
            ],
          ),
        ),
      ),
    );
  }

  static Future<UserGroupInfoModel?> showAddToGroupDialogAsync(
    BuildContext context,
    List<UserGroupInfoModel> userGroups,
  ) async {
    return showDialog<UserGroupInfoModel>(
      context: context,
      builder: (dialogContext) => ResponsiveSearchDialog<UserGroupInfoModel>(
        items: userGroups,
        description: CommonStrings.addToGroup,
        searchLabel: CommonStrings.search,
        filter: (group, query) => group.title
            .toLowerCase()
            .withoutDiacriticalMarks
            .contains(query.toLowerCase().withoutDiacriticalMarks),
        itemBuilder: (group) => ListTile(
          title: Text(group.title),
          onTap: () => Navigator.of(dialogContext).pop(group),
        ),
      ),
    );
  }

  static Future<LanguageModel?> chooseLanguage(BuildContext context) async {
    var locales = AppConfig.availableLanguages();
    final selectedLocale = await showDialog<LanguageModel>(
      context: context,
      builder: (dialogContext) => AppSimpleDialog(
        title: Text(CommonStrings.chooseLanguage),
        children: locales
            .map(
              (language) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(language),
                child: Text(language.name),
              ),
            )
            .toList(),
      ),
    );
    if (!context.mounted) return selectedLocale;
    if (selectedLocale != null) {
      context.setLocale(selectedLocale.locale);
      ToastHelper.Show(
        context,
        CommonStrings.languageSetTo(language: selectedLocale.name),
      );
    }
    return selectedLocale;
  }
}
