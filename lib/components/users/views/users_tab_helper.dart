import 'package:fstapp/components/users/user_strings.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/import/import_dialog_helper.dart';
import 'package:fstapp/components/single_data_grid/i_has_id.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/groups/group_participant_model.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/users/user_management_helper.dart';

class UsersTabHelper {
  /// Calls the import routine and then reloads users via the provided callback.
  static Future<void> importUsers(
      BuildContext context, Future<void> Function() reloadUsers) async {
    await ImportDialogHelper.import(context);
    await reloadUsers();
  }

  /// Returns the list of checked OccasionUserModel items from the data grid.
  static List<OccasionUserModel> getCheckedUsers(
      SingleDataGridController singleDataGrid) {
    return List<OccasionUserModel>.from(
      singleDataGrid.stateManager.refRows.originalList
          .where((row) => row.checked == true)
          .map((row) => OccasionUserModel.fromPlutoJson(row.toJson())),
    );
  }

  /// Changes passwords for all checked users.
  static Future<void> setPassword(
      BuildContext context, SingleDataGridController singleDataGrid) async {
    var users = getCheckedUsers(singleDataGrid);
    if (users.isEmpty) return;

    List<String> errorMessages = [];
    for (var u in users) {
      try {
        await UserManagementHelper.unsafeChangeUserPassword(context, u);
        ToastHelper.Show(context, UserStrings.passwordChanged);
      } catch (e) {
        String errorMessage = UserStrings.passwordChangeFailed(
            user: u.data?[Tb.occasion_users.data_email] ?? '[no email]',
            error: e.toString());
        ToastHelper.Show(context, errorMessage, severity: ToastSeverity.NotOk);
        errorMessages.add(errorMessage);
      }
    }
  }

  /// Opens the add-to-group dialog and updates the group with checked users.
  static Future<void> addToGroup(
      BuildContext context, SingleDataGridController singleDataGrid) async {
    var users = getCheckedUsers(singleDataGrid);
    var chosenGroup = await DialogHelper.showAddToGroupDialogAsync(
        context, await DbGroups.getAllUserGroupInfo());
    if (chosenGroup != null) {
      final existingIds =
          chosenGroup.participants!.map((p) => p.userInfo!.id).toSet();
      chosenGroup.participants!.addAll(users
          .where((u) => !existingIds.contains(u.id))
          .map(
              (u) => GroupParticipantModel(userInfo: UserInfoModel(id: u.id))));
      await DbGroups.updateUserGroupInfo(chosenGroup);
      ToastHelper.Show(
          context, CommonStrings.updatedItem(item: chosenGroup.title));
    }
  }

  /// Adds an existing user (from those not already added) to the occasion.
  /// [currentUsers] are the users already added in the current state.
  /// [reloadUsers] is a callback to trigger reloading the user list.
  static Future<void> addExisting(
      BuildContext context,
      SingleDataGridController singleDataGrid,
      List<IHasId> currentUsers,
      Future<void> Function() reloadUsers) async {
    var existing = await DbUsers.getAllUsersBasicsForUnit(
        RightsService.currentUnit()!.id!);
    var nonAdded = existing
        .where((u) => !currentUsers.any((cu) => cu.id == u.id))
        .toList();
    DialogHelper.chooseUser(context, (chosenUser) async {
      await DbUsers.addUserToOccasion(
          chosenUser.id!, RightsService.currentOccasionId()!);
      ToastHelper.Show(
          context, CommonStrings.updatedItem(item: chosenUser.toString()));
      await reloadUsers();
    }, nonAdded, CommonStrings.add);
  }

  static Future<void> addExistingToUnit(
      BuildContext context,
      SingleDataGridController singleDataGrid,
      List<ITrinaRowModel> currentUsers,
      Future<void> Function() reloadUsers,
      int unit) async {
    var existing = await DbUsers.getAllUsersBasicsForUnit(unit);
    var nonAdded = existing
        .where((u) => !currentUsers.any((cu) => cu.id == u.id))
        .toList();
    DialogHelper.chooseUser(context, (chosenUser) async {
      await DbUsers.addUserToUnit(chosenUser.id!, unit);
      ToastHelper.Show(
          context, CommonStrings.updatedItem(item: chosenUser.toString()));
      await reloadUsers();
    }, nonAdded, CommonStrings.add);
  }

  /// Sends sign-in codes to the checked users.
  static Future<void> invite(
      BuildContext context,
      SingleDataGridController singleDataGrid,
      Future<void> Function() reloadUsers) async {
    var users = getCheckedUsers(singleDataGrid);
    if (users.isEmpty) return;

    var alreadyInvitedUsers = users.where((user) => user.isInvited).toList();
    var newUsers = users.where((user) => !user.isInvited).toList();

    if (alreadyInvitedUsers.isNotEmpty) {
      var reinviteConfirm = await DialogHelper.showConfirmationDialog(
        context,
        UserStrings.invite,
        UserStrings.reinviteConfirm,
      );
      if (!reinviteConfirm) {
        await processInvites(context, newUsers);
        await reloadUsers();
        return;
      }
    }
    await processInvites(context, users);
    await reloadUsers();
  }

  static Future<void> processInvites(
      BuildContext context, List<OccasionUserModel> users,
      {int retryLimit = 3}) async {
    var confirm = await DialogHelper.showConfirmationDialog(
      context,
      UserStrings.invite,
      "${UserStrings.inviteInfo} (${users.length}):\n${users.map((u) => u.toBasicString()).join(",\n")}",
    );

    if (!confirm) return;

    Map<OccasionUserModel, int> retryAttempts = {
      for (var user in users) user: 0
    };
    List<Future<void> Function()> inviteFutures = users.map((user) {
      return () async {
        while (retryAttempts[user]! < retryLimit) {
          try {
            final statusRecorded = await AuthService.sendSignInCode(user);
            if (!statusRecorded) {
              ToastHelper.Show(
                context,
                UserStrings.invitationStatusFailed(
                    user: user.data![Tb.occasion_users.data_email]),
                severity: ToastSeverity.NotOk,
              );
              return;
            }
            ToastHelper.Show(
              context,
              UserStrings.invitedUser(
                  user: user.data![Tb.occasion_users.data_email]),
            );
            return;
          } catch (_) {
            retryAttempts[user] = retryAttempts[user]! + 1;
            if (retryAttempts[user]! >= retryLimit) {
              ToastHelper.Show(
                context,
                UserStrings.inviteFailed(
                    user: user.data![Tb.occasion_users.data_email],
                    retries: retryLimit.toString()),
                severity: ToastSeverity.NotOk,
              );
            }
            await Future.delayed(Duration(milliseconds: 500));
          }
        }
      };
    }).toList();

    await DialogHelper.showProgressDialogAsync(
      context,
      UserStrings.invite,
      inviteFutures.length,
      futures: inviteFutures,
      delay: Duration(milliseconds: 500),
    );
  }

  /// Sends application links to the checked users.
  /// [reloadUsers] is a callback to trigger reloading the user list.
  static Future<void> sendAppLinks(
      BuildContext context,
      SingleDataGridController singleDataGrid,
      Future<void> Function() reloadUsers) async {
    var users = getCheckedUsers(singleDataGrid);
    if (users.isEmpty) return;

    var alreadySentUsers = users
        .where(
            (user) => user.data?[Tb.occasion_users.data_appLinksSent] == true)
        .toList();
    var newUsers = users
        .where(
            (user) => user.data?[Tb.occasion_users.data_appLinksSent] != true)
        .toList();

    if (alreadySentUsers.isNotEmpty) {
      var resendConfirm = await DialogHelper.showConfirmationDialog(
        context,
        UserStrings.sendAppLinks,
        UserStrings.resendAppLinksConfirm,
      );
      if (!resendConfirm) {
        await processAppLinks(context, newUsers);
        await reloadUsers();
        return;
      }
    }
    await processAppLinks(context, users);
    await reloadUsers();
  }

  /// Processes sending application links to the given users.
  static Future<void> processAppLinks(
      BuildContext context, List<OccasionUserModel> users,
      {int retryLimit = 3}) async {
    var confirm = await DialogHelper.showConfirmationDialog(
      context,
      UserStrings.sendAppLinks,
      "${UserStrings.sendAppLinksInfo} (${users.length}):\n${users.map((u) => u.toBasicString()).join(",\n")}",
    );

    if (confirm) {
      Map<OccasionUserModel, int> retryAttempts = {
        for (var user in users) user: 0
      };

      List<Future<void> Function()> sendFutures = users.map((user) {
        return () async {
          while (retryAttempts[user]! < retryLimit) {
            try {
              final statusRecorded = await AuthService.sendAppLinks(user);
              if (!statusRecorded) {
                ToastHelper.Show(
                  context,
                  UserStrings.appLinksStatusFailed(
                      user: user.data![Tb.occasion_users.data_email]),
                  severity: ToastSeverity.NotOk,
                );
                return;
              }
              ToastHelper.Show(
                context,
                UserStrings.appLinksSentUser(
                    user: user.data![Tb.occasion_users.data_email]),
              );
              return;
            } catch (e) {
              retryAttempts[user] = retryAttempts[user]! + 1;
              if (retryAttempts[user]! >= retryLimit) {
                ToastHelper.Show(
                  context,
                  UserStrings.sendAppLinksFailed(
                      user: user.data![Tb.occasion_users.data_email],
                      retries: retryLimit.toString()),
                  severity: ToastSeverity.NotOk,
                );
                // Retrying the application-links delivery.
              }
              await Future.delayed(Duration(milliseconds: 500));
            }
          }
        };
      }).toList();

      await DialogHelper.showProgressDialogAsync(
        context,
        UserStrings.sendAppLinks,
        sendFutures.length,
        futures: sendFutures,
        delay: Duration(milliseconds: 500),
      );
    }
  }
}
