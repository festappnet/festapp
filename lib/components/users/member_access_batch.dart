import 'member_access_commands.dart';
import 'occasion_user_model.dart';
import 'unit_user_model.dart';

/// A saved membership snapshot, never the grid's unsaved role edits.
class MemberAccessRecipient {
  MemberAccessRecipient({
    required this.userId,
    required this.email,
    this.name = '',
    required this.roles,
  });
  final String userId;
  final String email;
  final String name;
  final Map<String, bool> roles;

  factory MemberAccessRecipient.fromUnit(UnitUserModel user) =>
      MemberAccessRecipient(
        userId: user.user!,
        email: user.emailReadonly ?? '',
        name: [
          user.name,
          user.surname,
        ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
        roles: {
          'is_manager': user.isManager == true,
          'is_editor': user.isEditor == true,
          'is_editor_view': user.isEditorView == true,
        },
      );

  factory MemberAccessRecipient.fromOccasion(OccasionUserModel user) =>
      MemberAccessRecipient(
        userId: user.user!,
        email: user.data?['email'] as String? ?? '',
        name: [
          user.data?['name'],
          user.data?['surname'],
        ].whereType<String>().where((s) => s.isNotEmpty).join(' '),
        roles: {
          'is_manager': user.isManager == true,
          'is_editor': user.isEditor == true,
          'is_editor_view': user.isEditorView == true,
          'is_editor_order': user.isEditorOrder == true,
          'is_editor_order_view': user.isEditorOrderView == true,
          'is_receptionist': user.isReceptionist == true,
          'is_approver': user.isApprover == true,
          'is_cleaning_crew': user.isCleaningCrew == true,
          'is_cleaning_blocked': user.isCleaningBlocked == true,
        },
      );
}

/// Resolves checked identities against saved data, including hidden role fields.
class MemberAccessSelection {
  MemberAccessSelection(
    Set<Object?> selectedIds,
    Iterable<Object> savedMembers,
  ) {
    for (final member in savedMembers) {
      final id = member is UnitUserModel
          ? member.user
          : (member as OccasionUserModel).user;
      if (id == null || !selectedIds.contains(id)) continue;
      recipients.add(
        member is UnitUserModel
            ? MemberAccessRecipient.fromUnit(member)
            : MemberAccessRecipient.fromOccasion(member as OccasionUserModel),
      );
    }
    unavailable = recipients.length != selectedIds.length;
  }
  final List<MemberAccessRecipient> recipients = [];
  late final bool unavailable;
}

/// One immutable intent per recipient. Confirmed queue admissions are not resent.
/// The command adapter retains its command identity after uncertain transport errors.
class MemberAccessBatch {
  MemberAccessBatch({
    required String scope,
    required int scopeId,
    required List<MemberAccessRecipient> recipients,
    required String communication,
    Map<String, bool> offeredRoles = const {},
  }) : requests = {
         for (final recipient in recipients)
           recipient.userId: {
             'scope': {'type': scope, 'id': scopeId},
             'operation': 'send_invitation',
             'communication': communication,
             'userId': recipient.userId,
             if (communication == 'invite_to_accept')
               'roles': Map<String, bool>.from(offeredRoles),
           },
       };

  final Map<String, Map<String, dynamic>> requests;
  final Map<String, Map<String, dynamic>> confirmed = {};
  final Map<String, String> failures = {};
  bool get complete => confirmed.length == requests.length;

  Future<void> send(
    Future<Map<String, dynamic>> Function(Map<String, dynamic>) sender, {
    required bool Function() isCurrent,
    required void Function() onProgress,
  }) async {
    for (final entry in requests.entries) {
      if (!isCurrent()) break;
      if (confirmed.containsKey(entry.key)) continue;
      failures.remove(entry.key);
      try {
        confirmed[entry.key] = await sender(entry.value);
      } on MemberAccessFailure catch (error) {
        failures[entry.key] = error.reasonCode;
        if (error.reasonCode == 'scope_denied') {
          onProgress();
          break;
        }
      } catch (_) {
        failures[entry.key] = 'failed';
      }
      onProgress();
    }
  }
}
