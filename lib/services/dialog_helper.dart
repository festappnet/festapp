import 'package:cross_file/cross_file.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
import 'package:select_dialog/select_dialog.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

export 'package:fstapp/services/dialog_helper_confirmation.dart';
export 'package:fstapp/services/dialog_helper_input.dart';
export 'package:fstapp/services/dialog_helper_progress.dart';

class ImportDialogChoice {
  final bool fromTickets;
  final XFile? fromFile;
  ImportDialogChoice({this.fromTickets = false, this.fromFile});
}

class DialogHelper {
  static Widget createDialogAction(String text, void Function() onPressed) {
    return TextButton(
      onPressed: onPressed,
      child: Text(text),
    );
  }

  static Future<ImportDialogChoice?> showImportDialog(
    BuildContext context,
    String titleMessage, {
    required bool showCsvImport,
    required bool showTicketImport,
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) =>
      InputDialogs.showImportDialog(
        context,
        titleMessage,
        showCsvImport: showCsvImport,
        showTicketImport: showTicketImport,
        confirmButtonMessage: confirmButtonMessage,
        cancelButtonMessage: cancelButtonMessage,
      );

  static Future<void> showInformationDialog(
          BuildContext context, String titleMessage, String textMessage,
          [String? buttonMessage]) =>
      ConfirmationDialogs.showInformationDialog(
          context, titleMessage, textMessage, buttonMessage);

  static Future<bool> showScanTicketCode(
    BuildContext context,
    String titleMessage,
    String textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) =>
      ConfirmationDialogs.showScanTicketCode(
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
  }) =>
      ConfirmationDialogs.showConfirmationDialog(
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
  }) =>
      ConfirmationDialogs.showConfirmationDialogRichText(
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
  }) =>
      ConfirmationDialogs.showConfirmationDialogRich(
        context: context,
        title: title,
        content: content,
        confirmButtonText: confirmButtonText,
        cancelButtonText: cancelButtonText,
      );

  static Future<bool> showNotificationPermissionDialog(
          BuildContext context) =>
      ConfirmationDialogs.showNotificationPermissionDialog(context);

  static Future<String?> showPasswordInputDialog(
    BuildContext context,
    String titleMessage,
    String hint, [
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  ]) =>
      InputDialogs.showPasswordInputDialog(
        context,
        titleMessage,
        hint,
        confirmButtonMessage,
        cancelButtonMessage,
      );

  static Future<XFile?> dropFilesHere(
    BuildContext context,
    String titleMessage,
    String confirmButtonMessage,
    String cancelButtonMessage, {
    Widget? headerContent,
  }) =>
      InputDialogs.dropFilesHere(
        context,
        titleMessage,
        confirmButtonMessage,
        cancelButtonMessage,
        headerContent: headerContent,
      );

  static Future<String?> showInputDialog({
    required BuildContext context,
    String? initialValue,
    required String dialogTitle,
    required String labelText,
  }) =>
      InputDialogs.showInputDialog(
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
  }) =>
      ProgressDialogs.showProgressDialogAsync(
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
  }) =>
      ProgressDialogs.showFutureProgressDialog<T>(
        context: context,
        title: title,
        futureCallback: futureCallback,
      );

  static Future<void> chooseUser(
      BuildContext context,
      void Function(UserInfoModel) onPressedAction,
      List<UserInfoModel> allUsers,
      String setText,
      {bool useRootNavigator = true}) async {
    showDialog(
      useRootNavigator: useRootNavigator,
      context: context,
      builder: (context) => ResponsiveSearchDialog<UserInfoModel>(
        items: allUsers,
        searchLabel: CommonStrings.searchParticipants,
        filter: (person, query) {
          final q = query.toLowerCase().withoutDiacriticalMarks;
          return (person.name
                      ?.toLowerCase()
                      .withoutDiacriticalMarks
                      .contains(q) ??
                  false) ||
              (person.surname
                      ?.toLowerCase()
                      .withoutDiacriticalMarks
                      .contains(q) ??
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
                  child: Text(setText)),
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
    UserGroupInfoModel? selectedGroup;
    await SelectDialog.showModal<UserGroupInfoModel>(
      context,
      label: CommonStrings.addToGroup,
      items: userGroups,
      searchBoxDecoration: InputDecoration(hintText: CommonStrings.search),
      selectedValue: selectedGroup,
      itemBuilder:
          (BuildContext context, UserGroupInfoModel item, bool isSelected) {
        return Container(
          decoration: !isSelected
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.white,
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
          child: TextButton(
            onPressed: null,
            child: Text(item.title),
          ),
        );
      },
      onChange: (selected) {
        selectedGroup = selected;
      },
    );
    return selectedGroup;
  }

  static Future<LanguageModel?> chooseLanguage(
    BuildContext context,
  ) async {
    var locales = AppConfig.availableLanguages();
    LanguageModel? selectedLocale;
    await SelectDialog.showModal<LanguageModel>(
      context,
      label: CommonStrings.chooseLanguage,
      items: locales,
      showSearchBox: false,
      selectedValue: selectedLocale,
      itemBuilder: (BuildContext context, LanguageModel item, bool isSelected) {
        return Container(
          decoration: !isSelected
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.white,
                  border: Border.all(
                    color: Theme.of(context).primaryColor,
                  ),
                ),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text(
              item.name,
              style: TextStyle(
                color: ThemeConfig.blackColor(context),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        );
      },
      onChange: (selected) {
        selectedLocale = selected;
      },
    );
    if (selectedLocale != null) {
      context.setLocale(selectedLocale!.locale);
      ToastHelper.Show(context,
          CommonStrings.languageSetTo(language: selectedLocale!.name));
    }
    return selectedLocale;
  }
}
