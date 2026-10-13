import 'package:flutter/material.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/users/companion/companion_model.dart';
import 'package:fstapp/components/users/companion/db_companions.dart';
import 'package:fstapp/components/users/user_strings.dart';
import 'package:fstapp/services/dialog_helper.dart';
import 'package:fstapp/services/connectivity_service.dart';
import 'package:fstapp/services/exception_handler.dart';

class CompanionManagementDialog extends StatefulWidget {
  const CompanionManagementDialog({
    super.key,
    required this.allowUserCreate,
    required this.maxCompanions,
    required this.companions,
    required this.refreshData,
    this.createCompanion,
    this.deleteCompanion,
    this.reloadCompanions,
  });

  final bool allowUserCreate;
  final int maxCompanions;
  final List<CompanionModel> companions;
  final Future<void> Function() refreshData;
  final Future<void> Function(String name)? createCompanion;
  final Future<void> Function(CompanionModel companion)? deleteCompanion;
  final Future<List<CompanionModel>> Function()? reloadCompanions;

  @override
  State<CompanionManagementDialog> createState() =>
      _CompanionManagementDialogState();
}

class _CompanionManagementDialogState extends State<CompanionManagementDialog> {
  final _nameController = TextEditingController();
  late List<CompanionModel> _companions = widget.companions;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _companions.length >= widget.maxCompanions) return;
    final ok = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () =>
          (widget.createCompanion ?? DbCompanions.create)(name),
    );
    if (!ok) return;
    await _reload();
  }

  Future<void> _delete(CompanionModel companion) async {
    final confirmed = await DialogHelper.showConfirmationDialog(context,
        UserStrings.deleteCompanion, UserStrings.deleteCompanionConfirm);
    if (!confirmed || !mounted) return;
    final ok = await ExceptionHandler.guardVoid(
      context,
      futureFunction: () =>
          (widget.deleteCompanion ?? DbCompanions.deleteSelf)(companion),
    );
    if (!ok) return;
    await _reload();
  }

  Future<void> _reload() async {
    await widget.refreshData();
    final companions =
        await (widget.reloadCompanions ?? DbCompanions.getAllCompanions)();
    if (mounted) setState(() => _companions = companions);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOfflineNotifier,
      builder: (context, isOffline, _) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(CommonStrings.companions),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.allowUserCreate &&
                      _companions.length < widget.maxCompanions)
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                              labelText: UserStrings.companionName),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: isOffline ? null : _create,
                        child: Text(UserStrings.createCompanion),
                      ),
                    ]),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final companion in _companions)
                          ListTile(
                            title: Text(companion.fullName),
                            subtitle: Text(companion.groupTitle.isEmpty
                                ? UserStrings.noGroup
                                : companion.groupTitle),
                            trailing: companion.origin == 'self_created' &&
                                    companion.canOwnerDelete
                                ? IconButton(
                                    tooltip: UserStrings.deleteCompanion,
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: isOffline
                                        ? null
                                        : () => _delete(companion),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ));
}

class CompanionAttendanceDialog extends StatefulWidget {
  const CompanionAttendanceDialog({
    super.key,
    required this.eventId,
    required this.companions,
    required this.canSignIn,
    required this.refreshData,
    this.changeAttendance,
    this.reloadCompanions,
  });

  final int eventId;
  final List<CompanionModel> companions;
  final bool Function() canSignIn;
  final Future<void> Function() refreshData;
  final Future<void> Function(
      int eventId, CompanionModel companion, bool signIn)? changeAttendance;
  final Future<List<CompanionModel>> Function()? reloadCompanions;

  @override
  State<CompanionAttendanceDialog> createState() =>
      _CompanionAttendanceDialogState();
}

class _CompanionAttendanceDialogState extends State<CompanionAttendanceDialog> {
  late List<CompanionModel> _companions = widget.companions;

  Future<void> _change(CompanionModel companion, bool signIn) async {
    final changeAttendance = widget.changeAttendance;
    if (changeAttendance != null) {
      await changeAttendance(widget.eventId, companion, signIn);
    } else if (signIn) {
      await DbCompanions.signIn(context, widget.eventId, companion);
    } else {
      await DbCompanions.signOut(context, widget.eventId, companion);
    }
    await widget.refreshData();
    final companions =
        await (widget.reloadCompanions ?? DbCompanions.getAllCompanions)();
    if (mounted) setState(() => _companions = companions);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
      valueListenable: ConnectivityService.isOfflineNotifier,
      builder: (context, isOffline, _) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(CommonStrings.companions),
            content: SizedBox(
              width: 480,
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final companion in _companions)
                    ListTile(
                      title: Text(companion.fullName),
                      subtitle: Text(companion.groupTitle.isEmpty
                          ? UserStrings.noGroup
                          : companion.groupTitle),
                      trailing: companion.isSignedIn(widget.eventId)
                          ? TextButton(
                              onPressed: isOffline
                                  ? null
                                  : () => _change(companion, false),
                              child: Text(UserStrings.companionSignOut),
                            )
                          : FilledButton(
                              onPressed: !isOffline && widget.canSignIn()
                                  ? () => _change(companion, true)
                                  : null,
                              child: Text(UserStrings.companionSignIn),
                            ),
                    ),
                ],
              ),
            ),
          ));
}
