import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class ConfirmationDialogs {
  static Future<void> showInformationDialog(
      BuildContext context, String titleMessage, String textMessage,
      [String? buttonMessage]) async {
    await showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: Text(titleMessage),
            content: SelectableText(textMessage),
            actions: [
              ElevatedButton(
                child: Text(buttonMessage ?? CommonStrings.ok),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        });
  }

  static Future<bool> showScanTicketCode(
    BuildContext context,
    String titleMessage,
    String textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) async {
    bool result = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titleMessage),
          content: Container(),
          actions: [
            ElevatedButton(
              child: Text(confirmButtonMessage ?? CommonStrings.ok),
              onPressed: () {
                result = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return result;
  }

  static Future<bool> showConfirmationDialog(
    BuildContext context,
    String titleMessage,
    String textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) async {
    bool result = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titleMessage),
          content: SingleChildScrollView(child: Text(textMessage)),
          actions: [
            TextButton(
              child: Text(cancelButtonMessage ?? CommonStrings.storno),
              onPressed: () {
                result = false;
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text(confirmButtonMessage ?? CommonStrings.ok),
              onPressed: () {
                result = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return result;
  }

  static Future<bool> showConfirmationDialogRichText(
    BuildContext context,
    String titleMessage,
    Text textMessage, {
    String? confirmButtonMessage,
    String? cancelButtonMessage,
  }) async {
    bool result = false;
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(titleMessage),
          content: SingleChildScrollView(child: textMessage),
          actions: [
            TextButton(
              child: Text(cancelButtonMessage ?? CommonStrings.storno),
              onPressed: () {
                result = false;
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text(confirmButtonMessage ?? CommonStrings.ok),
              onPressed: () {
                result = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return result;
  }

  static Future<bool> showConfirmationDialogRich({
    required BuildContext context,
    required String title,
    required Widget content,
    String? confirmButtonText,
    String? cancelButtonText,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: content,
          actions: [
            TextButton(
              child: Text(cancelButtonText ?? CommonStrings.storno),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
            ElevatedButton(
              child: Text(confirmButtonText ?? CommonStrings.ok),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  static Future<bool> showNotificationPermissionDialog(
      BuildContext context) async {
    bool result = false;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(CommonStrings.notifications),
          content: SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text(CommonStrings.notificationsInfo),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: Text(CommonStrings.disable),
              onPressed: () {
                result = false;
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: Text(CommonStrings.enable),
              onPressed: () async {
                result = true;
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
    return result;
  }
}
