import 'package:flutter/material.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

class UserManagementHelper {
  /// Prompts for and sets a new password for a single user.
  /// Throws an exception if the process fails.
  static Future<void> unsafeChangeUserPassword(
      BuildContext context, OccasionUserModel user,
      {Future<String?> Function(BuildContext context)? requestPassword,
      Future<void> Function(OccasionUserModel user, String password)?
          changePassword}) async {
    if (user.user == null) {
      throw Exception("User must be created first.");
    }
    var pw = requestPassword != null
        ? await requestPassword(context)
        : await DialogHelper.showPasswordInputDialog(
            context, CommonStrings.password, UserStrings.insertHere);
    if (pw == null || pw.isEmpty) {
      // User cancelled the dialog, so we can return without an error.
      // Or throw an exception if a password MUST be set.
      throw Exception("Password has not been set.");
    }

    // The try-catch block is removed from here.
    // The exception from the service will now be propagated up to the caller.
    if (changePassword != null) {
      await changePassword(user, pw);
    } else {
      await AuthService.unsafeChangeUserPassword(user, pw);
    }
  }
}
