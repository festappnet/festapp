import 'package:flutter/material.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';
import 'package:fstapp/components/users/occasion_user_model.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/database_tables/tb.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/exception_handler.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/toast_helper.dart';

typedef ChangeCompanion = Future<void> Function(
  String ownerId,
  String companionId,
  bool detach,
);

class CompanionAdminDialog extends StatefulWidget {
  const CompanionAdminDialog({
    super.key,
    required this.owner,
    required this.users,
    required this.maxCompanions,
    required this.onChanged,
    this.changeCompanion,
  });

  final OccasionUserModel owner;
  final List<OccasionUserModel> users;
  final int maxCompanions;
  final Future<void> Function() onChanged;
  final ChangeCompanion? changeCompanion;

  @override
  State<CompanionAdminDialog> createState() => _CompanionAdminDialogState();
}

class _CompanionAdminDialogState extends State<CompanionAdminDialog> {
  String query = '';

  String _name(OccasionUserModel user) => [
        user.data?[Tb.occasion_users.data_name],
        user.data?[Tb.occasion_users.data_surname],
      ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' ');

  String _email(OccasionUserModel user) =>
      user.data?[Tb.occasion_users.data_email] ?? '';

  String _group(OccasionUserModel user) =>
      user.groupTitle?.trim().isNotEmpty == true
          ? user.groupTitle!
          : UserStrings.noGroup;

  bool _ownerHasCompanion(String? userId) =>
      widget.users.any((user) => user.companionOwnerId == userId);

  String? _blockedReason(OccasionUserModel candidate, int currentCount) {
    if (widget.owner.companionOwnerId != null) {
      return UserStrings.companionOwnerIsAssigned;
    }
    if (currentCount >= widget.maxCompanions) {
      return UserStrings.companionLimitReached;
    }
    if (candidate.companionOwnerId != null) {
      return UserStrings.companionAlreadyAssigned;
    }
    if (_ownerHasCompanion(candidate.user)) {
      return UserStrings.companionOwnsAnother;
    }
    return null;
  }

  Future<void> _change(OccasionUserModel candidate, bool detach) async {
    final ownerId = widget.owner.user;
    final candidateId = candidate.user;
    if (ownerId == null || candidateId == null) return;
    final confirmed = await DialogHelper.showConfirmationDialog(
      context,
      detach ? UserStrings.unassignCompanion : UserStrings.assignCompanion,
      '${_name(widget.owner)} · ${_email(widget.owner)} · ${_group(widget.owner)} ↔ '
      '${_name(candidate)} · ${_email(candidate)} · ${_group(candidate)}',
    );
    if (!confirmed || !mounted) return;
    final ok = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () {
        final changeCompanion = widget.changeCompanion;
        if (changeCompanion != null) {
          return changeCompanion(ownerId, candidateId, detach);
        }
        return detach
            ? DbCompanions.unassignExisting(ownerId, candidateId)
            : DbCompanions.assignExisting(ownerId, candidateId);
      },
    );
    if (ok) {
      if (!detach) {
        await ToastHelper.Show(context, UserStrings.companionAssigned);
      }
      await widget.onChanged();
      if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.users
        .where((user) => user.companionOwnerId == widget.owner.user)
        .toList(growable: false);
    final normalized = query.toLowerCase();
    final candidates = widget.users.where((user) {
      if (user.user == widget.owner.user) return false;
      if (user.companionOwnerId == widget.owner.user) return false;
      final haystack =
          '${_name(user)} ${_email(user)} ${_group(user)}'.toLowerCase();
      return haystack.contains(normalized);
    }).toList(growable: false);
    return ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOfflineNotifier,
      builder: (context, isOffline, _) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(UserStrings.manageCompanions),
        content: SizedBox(
          width: 680,
          height: 620,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ListTile(
              title: Text(_name(widget.owner)),
              subtitle:
                  Text('${_email(widget.owner)} · ${_group(widget.owner)}'),
            ),
            for (final companion in current)
              ListTile(
                leading: const Icon(Icons.link),
                title: Text(_name(companion)),
                subtitle: Text('${_email(companion)} · ${_group(companion)}'),
                trailing: TextButton(
                  onPressed: isOffline ? null : () => _change(companion, true),
                  child: Text(UserStrings.unassignCompanion),
                ),
              ),
            TextField(
              decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: UserStrings.searchCompanion),
              onChanged: (value) => setState(() => query = value),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: candidates.length,
                itemBuilder: (context, index) {
                  final candidate = candidates[index];
                  final blockedReason =
                      _blockedReason(candidate, current.length);
                  return ListTile(
                    title: Text(_name(candidate)),
                    subtitle: Text([
                      '${_email(candidate)} · ${_group(candidate)}',
                      if (blockedReason != null) blockedReason,
                    ].join('\n')),
                    isThreeLine: blockedReason != null,
                    trailing: FilledButton(
                      onPressed: !isOffline && blockedReason == null
                          ? () => _change(candidate, false)
                          : null,
                      child: Text(UserStrings.assignCompanion),
                    ),
                  );
                },
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
