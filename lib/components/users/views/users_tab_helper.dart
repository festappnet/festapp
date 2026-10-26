import 'package:uuid/uuid.dart';
import 'package:fstapp/services/batch_progress_dialog.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/components/users/occasion_team_invitation_strings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/single_data_grid/i_has_id.dart';
import 'package:fstapp/components/single_data_grid/pluto_abstract.dart';
import 'package:fstapp/components/single_data_grid/single_data_grid_controller.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/data_services/auth_service.dart';
import 'package:fstapp/components/groups/db_groups.dart';
import 'package:fstapp/components/users/db_users.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/components/users/user_management_helper.dart';

class UsersTabHelper {
  /// Returns the list of checked OccasionUserModel items from the data grid.
  static List<OccasionUserModel> getCheckedUsers(
    SingleDataGridController singleDataGrid,
  ) {
    return List<OccasionUserModel>.from(
      singleDataGrid.stateManager.refRows.originalList
          .where((row) => row.checked == true)
          .map((row) => OccasionUserModel.fromPlutoJson(row.toJson())),
    );
  }

  /// Changes passwords for all checked users.
  static Future<void> setPassword(
    BuildContext context,
    SingleDataGridController singleDataGrid,
  ) async {
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
          error: e.toString(),
        );
        ToastHelper.Show(context, errorMessage, severity: ToastSeverity.NotOk);
        errorMessages.add(errorMessage);
      }
    }
  }

  /// Opens the add-to-group dialog and updates the group with checked users.
  static Future<void> addToGroup(
    BuildContext context,
    SingleDataGridController singleDataGrid,
  ) async {
    var users = getCheckedUsers(singleDataGrid);
    var chosenGroup = await DialogHelper.showAddToGroupDialogAsync(
      context,
      await DbGroups.getAllUserGroupInfo(),
    );
    if (chosenGroup != null) {
      await DbGroups.addMembers(
        chosenGroup,
        users.map<String>((u) => u.id as String).toList(),
      );
      ToastHelper.Show(
        context,
        CommonStrings.updatedItem(item: chosenGroup.title),
      );
    }
  }

  /// Adds an existing user (from those not already added) to the occasion.
  /// [currentUsers] are the users already added in the current state.
  /// [reloadUsers] is a callback to trigger reloading the user list.
  static Future<void> addExisting(
    BuildContext context,
    SingleDataGridController singleDataGrid,
    List<IHasId> currentUsers,
    Future<void> Function() reloadUsers,
  ) async {
    var existing = await DbUsers.getAllUsersBasicsForUnit(
      RightsService.currentUnit()!.id!,
    );
    var nonAdded = existing
        .where((u) => !currentUsers.any((cu) => cu.id == u.id))
        .toList();
    if (!context.mounted) return;
    await DialogHelper.chooseUser(
      context,
      (chosenUser) async {
        await DbUsers.addUserToOccasion(
          chosenUser.id!,
          RightsService.currentOccasionId()!,
        );
        ToastHelper.Show(
          context,
          CommonStrings.updatedItem(item: chosenUser.toString()),
        );
        await reloadUsers();
      },
      nonAdded,
      CommonStrings.add,
      description: UserStrings.existingParticipantsScope,
      emptyMessage: UserStrings.noExistingParticipants,
    );
  }

  static Future<void> addExistingToUnit(
    BuildContext context,
    SingleDataGridController singleDataGrid,
    List<ITrinaRowModel> currentUsers,
    Future<void> Function() reloadUsers,
    int unit,
  ) async {
    var existing = await DbUsers.getAllUsersBasicsForUnit(unit);
    var nonAdded = existing
        .where((u) => !currentUsers.any((cu) => cu.id == u.id))
        .toList();
    DialogHelper.chooseUser(
      context,
      (chosenUser) async {
        await DbUsers.addUserToUnit(chosenUser.id!, unit);
        ToastHelper.Show(
          context,
          CommonStrings.updatedItem(item: chosenUser.toString()),
        );
        await reloadUsers();
      },
      nonAdded,
      CommonStrings.add,
    );
  }

  /// Sends sign-in codes to the checked users.
  static Future<void> invite(
    BuildContext context,
    SingleDataGridController singleDataGrid,
    Future<void> Function() reloadUsers,
  ) async {
    var users = getCheckedUsers(singleDataGrid);
    if (users.isEmpty) return;

    var alreadyInvitedUsers = users.where((user) => user.isInvited).toList();
    var newUsers = users.where((user) => !user.isInvited).toList();

    if (alreadyInvitedUsers.isNotEmpty) {
      var reinviteConfirm = await DialogHelper.showConfirmationDialog(
        context,
        UserStrings.invite,
        OccasionTeamInvitationStrings.text('legacyReinviteConfirm'),
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
    BuildContext context,
    List<OccasionUserModel> users, {
    int retryLimit = 3,
  }) async {
    if (users.isEmpty) return;
    var confirm = await DialogHelper.showConfirmationDialog(
      context,
      UserStrings.invite,
      "${OccasionTeamInvitationStrings.text('legacyInviteHint')} (${users.length}):\n${users.map((u) => u.toBasicString()).join(",\n")}",
    );

    if (!confirm) return;

    if (!context.mounted) return;
    final tasks = users.map((user) {
      // Transport retries and queued checks share an intent. A terminal failure
      // permits a new attempt; SQL still joins any unresolved queued message.
      var requestId = const Uuid().v4();
      return BatchTask(
        label: user.toBasicString(),
        run: () async {
          for (var attempt = 0; attempt < retryLimit; attempt++) {
            try {
              final status = await AuthService.sendSignInCode(
                user,
                requestId: requestId,
              );
              return status == InvitationDeliveryStatus.sent
                  ? BatchTaskOutcome.completed
                  : BatchTaskOutcome.deferred;
            } catch (_) {
              if (attempt + 1 >= retryLimit) {
                requestId = const Uuid().v4();
                rethrow;
              }
              await Future<void>.delayed(const Duration(milliseconds: 500));
            }
          }
          throw StateError('Invitation retry limit exhausted');
        },
      );
    }).toList();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchProgressDialog(
        title: UserStrings.invite,
        tasks: tasks,
        successLabel: UserStrings.invitationSent,
        failureLabel: UserStrings.invitationFailed,
        retryLabel: UserStrings.retryFailedInvitations,
        deferredLabel: UserStrings.invitationQueued,
      ),
    );
  }

  /// Sends application links to the checked users.
  /// [reloadUsers] is a callback to trigger reloading the user list.
  static Future<void> sendAppLinks(
    BuildContext context,
    SingleDataGridController singleDataGrid,
    Future<void> Function() reloadUsers,
  ) async {
    var users = getCheckedUsers(singleDataGrid);
    if (users.isEmpty) return;

    var alreadySentUsers = users
        .where(
          (user) => user.data?[Tb.occasion_users.data_appLinksSent] == true,
        )
        .toList();
    var newUsers = users
        .where(
          (user) => user.data?[Tb.occasion_users.data_appLinksSent] != true,
        )
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
    BuildContext context,
    List<OccasionUserModel> users, {
    int retryLimit = 3,
  }) async {
    var confirm = await DialogHelper.showConfirmationDialog(
      context,
      UserStrings.sendAppLinks,
      "${UserStrings.sendAppLinksInfo} (${users.length}):\n${users.map((u) => u.toBasicString()).join(",\n")}",
    );

    if (confirm) {
      Map<OccasionUserModel, int> retryAttempts = {
        for (var user in users) user: 0,
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
                    user: user.data![Tb.occasion_users.data_email],
                  ),
                  severity: ToastSeverity.NotOk,
                );
                return;
              }
              ToastHelper.Show(
                context,
                UserStrings.appLinksSentUser(
                  user: user.data![Tb.occasion_users.data_email],
                ),
              );
              return;
            } catch (e) {
              retryAttempts[user] = retryAttempts[user]! + 1;
              if (retryAttempts[user]! >= retryLimit) {
                ToastHelper.Show(
                  context,
                  UserStrings.sendAppLinksFailed(
                    user: user.data![Tb.occasion_users.data_email],
                    retries: retryLimit.toString(),
                  ),
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
