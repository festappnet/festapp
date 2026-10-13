import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/activities/activity_model.dart';
import 'package:fstapp/services/toast_helper.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'activities_component_strings.dart';
import 'activity_timeline_controller.dart';
import 'constants.dart';

class UsersPanel extends StatelessWidget {
  final ActivityTimelineController controller;

  const UsersPanel({
    super.key,
    required this.controller,
  });

  void _showUserAssignmentsDialog(
      BuildContext context, ActivityUserInfoModel user) {
    // ... (This method is unchanged)
    final allUserAssignments = controller.activityAssignments.values
        .expand((assignments) => assignments)
        .where((a) => a.userInfo == user.id && a.data?['isDragPreview'] != true)
        .toList();

    allUserAssignments.sort((a, b) {
      if (a.startTime == null || b.startTime == null) return 0;
      return a.startTime!.compareTo(b.startTime!);
    });

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _UserAssignmentsDialog(
        sourceUser: user,
        assignments: allUserAssignments,
        allActivities: controller.allActivities,
        allUsers: controller.allUsers,
        onCopyToUser: controller.onCopyAssignments,
        onDeleteAssignments: controller.onDeleteAssignments,
        onRemoveLink: controller.onRemoveLinkFromAssignment,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... (This method is unchanged)
    final normalizedFilter =
        Utilities.removeDiacritics(controller.userFilter.toLowerCase());
    final filtered = controller.allUsers
        .where((u) =>
            Utilities.removeDiacritics(u.toFullNameString().toLowerCase())
                .contains(normalizedFilter))
        .toList();
    final hintColor = controller.hintColor;
    final textColor = controller.textColor;

    return Container(
      padding: const EdgeInsets.all(2),
      color: controller.isDark ? Colors.grey[850] : Colors.grey[100],
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: TextField(
              style: TextStyle(fontSize: 12, color: textColor),
              decoration: InputDecoration(
                hintText: ActivitiesComponentStrings.hintSearchUsers,
                hintStyle: TextStyle(color: hintColor, fontSize: 12),
                isDense: true,
                alignLabelWithHint: true,
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 8, right: 4),
                  child: Icon(Icons.search, size: 14, color: hintColor),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 24, minHeight: 24),
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.transparent,
              ),
              onChanged: controller.onUserFilterChanged,
            ),
          ),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 60,
                mainAxisExtent: 60,
                mainAxisSpacing: 2,
                crossAxisSpacing: 2,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final u = filtered[index];
                final initials = u.getInitials();
                final color = ActivityConstants.darkUserColors[
                    u.hashCode % ActivityConstants.darkUserColors.length];
                final avatarTextColor = Colors.white;
                final assignedHours =
                    controller.userAssignedHours[u.id] ?? Duration.zero;
                final bool hasAssignments = assignedHours.inMinutes > 0;
                final String hoursText = hasAssignments
                    ? '${assignedHours.inHours}h ${assignedHours.inMinutes.remainder(60)}m'
                    : '';

                return Draggable<ActivityUserInfoModel>(
                  data: u,
                  onDragStarted: () {
                    controller.hideAssignmentDetailOverlay();
                    controller.onUserDragStarted(u);
                  },
                  onDragEnd: (_) => controller.onUserDragEnd(),
                  feedback: Material(
                    color: Colors.transparent,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: color.withOpacity(0.8),
                            border: Border.all(color: color, width: 1.5),
                          ),
                          child: Center(
                            child: Text(
                              initials,
                              style: TextStyle(
                                color: avatarTextColor,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          u.toFullNameString(),
                          style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              decoration: TextDecoration.none),
                        ),
                      ],
                    ),
                  ),
                  child: GestureDetector(
                    onTap: () => _showUserAssignmentsDialog(context, u),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                margin: const EdgeInsets.only(top: 2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: color,
                                  border: Border.all(
                                      color: color.withOpacity(0.5),
                                      width: 1.0),
                                ),
                                child: Center(
                                  child: Text(
                                    initials,
                                    style: TextStyle(
                                      color: avatarTextColor,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              if (hasAssignments)
                                Positioned(
                                  top: -6,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: controller.isDark
                                          ? Colors.orange[800]
                                          : Colors.orange[100],
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      hoursText,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: controller.isDark
                                            ? Colors.white
                                            : Colors.black87,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 2, left: 1, right: 1),
                            child: Text(
                              u.toFullNameString(),
                              style: TextStyle(
                                fontSize: 10,
                                color: textColor.withOpacity(0.8),
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              softWrap: true,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class _UserAssignmentsDialog extends StatefulWidget {
  final ActivityUserInfoModel sourceUser;
  final List<ActivityAssignmentModel> assignments;
  final List<ActivityModel> allActivities;
  final List<ActivityUserInfoModel> allUsers;
  final Function(ActivityUserInfoModel, List<ActivityAssignmentModel>)
      onCopyToUser;
  final Function(List<ActivityAssignmentModel>) onDeleteAssignments;
  final Function(ActivityAssignmentModel, dynamic) onRemoveLink;

  const _UserAssignmentsDialog({
    required this.sourceUser,
    required this.assignments,
    required this.allActivities,
    required this.allUsers,
    required this.onCopyToUser,
    required this.onDeleteAssignments,
    required this.onRemoveLink,
  });

  @override
  _UserAssignmentsDialogState createState() => _UserAssignmentsDialogState();
}

class _UserAssignmentsDialogState extends State<_UserAssignmentsDialog> {
  late List<ActivityAssignmentModel> _localAssignments;
  late List<dynamic> _displayList;
  final Set<ActivityAssignmentModel> _selectedAssignments = {};
  bool _isAllSelected = false;
  bool _hasShownCopyToast = false;
  bool _hasShownDeleteToast = false;

  @override
  void initState() {
    super.initState();
    _localAssignments = List.from(widget.assignments);
    _rebuildDisplayList();
  }

  void _rebuildDisplayList() {
    _displayList = [];
    final groupedAssignments =
        groupBy<ActivityAssignmentModel, DateTime>(_localAssignments, (a) {
      final startTime = a.startTime!.toLocal();
      return DateTime(startTime.year, startTime.month, startTime.day);
    });

    for (final entry in groupedAssignments.entries) {
      _displayList.add(entry.key);
      _displayList.addAll(entry.value);
    }
  }

  void _handleSelectAll(bool? value) {
    setState(() {
      _isAllSelected = value ?? false;
      _selectedAssignments.clear();
      if (_isAllSelected) {
        _selectedAssignments.addAll(_localAssignments);
      }
    });
  }

  void _showTargetUserSelection() async {
    final otherUsers =
        widget.allUsers.where((u) => u.id != widget.sourceUser.id).toList();

    final ActivityUserInfoModel? targetUser = await showDialog(
      context: context,
      builder: (ctx) => _UserSearchDialog(allUsers: otherUsers),
    );

    if (targetUser != null && mounted) {
      widget.onCopyToUser(targetUser, _selectedAssignments.toList());
      if (!_hasShownCopyToast) {
        final count = _selectedAssignments.length;
        ToastHelper.Show(
          context,
          ActivitiesComponentStrings.toastAssignmentsCopiedInDialog(
              count, targetUser.toFullNameString()),
          severity: ToastSeverity.Ok,
        );
        _hasShownCopyToast = true;
      }
      setState(() {
        _selectedAssignments.clear();
        _isAllSelected = false;
      });
    }
  }

  void _deleteSelected() {
    if (_selectedAssignments.isEmpty || !mounted) return;
    widget.onDeleteAssignments(_selectedAssignments.toList());
    if (!_hasShownDeleteToast) {
      final count = _selectedAssignments.length;
      ToastHelper.Show(
        context,
        ActivitiesComponentStrings.toastAssignmentsDeletedInDialog(count),
        severity: ToastSeverity.Ok,
      );
      _hasShownDeleteToast = true;
    }
    setState(() {
      _localAssignments.removeWhere((a) => _selectedAssignments.contains(a));
      _selectedAssignments.clear();
      _isAllSelected = false;
      _rebuildDisplayList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // ... build method is unchanged from the previous version ...
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final assignedHours = _localAssignments.fold<Duration>(
      Duration.zero,
      (prev, e) =>
          prev + (e.endTime?.difference(e.startTime!) ?? Duration.zero),
    );
    final String hoursText =
        '${assignedHours.inHours}h ${assignedHours.inMinutes.remainder(60)}m';

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24.0, 16.0, 16.0, 8.0),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  ActivitiesComponentStrings.dialogTitleAssignmentsFor(
                      widget.sourceUser.toFullNameString()),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  '${ActivitiesComponentStrings.labelTotalTime}: $hoursText',
                  style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white70 : Colors.black54,
                      fontWeight: FontWeight.normal),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: ActivitiesComponentStrings.tooltipCloseDialog,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.5,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: Row(
                children: [
                  if (_localAssignments.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                            value: _isAllSelected, onChanged: _handleSelectAll),
                        Text(ActivitiesComponentStrings.textSelectAll,
                            style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  const Spacer(),
                  if (_localAssignments.isNotEmpty)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          icon: Icon(Icons.delete_outline, size: 18),
                          label: Text(ActivitiesComponentStrings.menuDelete),
                          onPressed: _selectedAssignments.isNotEmpty
                              ? _deleteSelected
                              : null,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                              visualDensity: VisualDensity.compact),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy_all_outlined, size: 16),
                          label:
                              Text(ActivitiesComponentStrings.buttonCopyToUser),
                          onPressed: _selectedAssignments.isNotEmpty
                              ? _showTargetUserSelection
                              : null,
                          style: ElevatedButton.styleFrom(
                              visualDensity: VisualDensity.compact),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            const Divider(),
            Expanded(
              child: _displayList.isEmpty
                  ? Center(
                      child: Text(
                          ActivitiesComponentStrings.textNoAssignmentsForUser))
                  : ListView.builder(
                      itemCount: _displayList.length,
                      itemBuilder: (ctx, index) {
                        final item = _displayList[index];

                        if (item is DateTime) {
                          // Build a day header
                          return Padding(
                            padding:
                                const EdgeInsets.only(top: 16.0, bottom: 8.0),
                            child: Text(
                              DateFormat(
                                      ActivitiesComponentStrings
                                          .dateFormatDayMonth,
                                      context.locale.languageCode)
                                  .format(item)
                                  .toUpperCase(),
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Theme.of(context).primaryColor),
                            ),
                          );
                        }

                        if (item is ActivityAssignmentModel) {
                          // Build an assignment item
                          final assignment = item;
                          final activity = widget.allActivities
                              .firstWhereOrNull(
                                  (a) => a.id == assignment.activityId);
                          final isSelected =
                              _selectedAssignments.contains(assignment);
                          final timeFormatter =
                              DateFormat.Hm(context.locale.languageCode);

                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.symmetric(
                                vertical: 4, horizontal: 2),
                            child: InkWell(
                              onTap: () => setState(() {
                                if (isSelected) {
                                  _selectedAssignments.remove(assignment);
                                } else {
                                  _selectedAssignments.add(assignment);
                                }
                              }),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (value) => setState(() {
                                        if (value == true) {
                                          _selectedAssignments.add(assignment);
                                        } else {
                                          _selectedAssignments
                                              .remove(assignment);
                                        }
                                      }),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            activity?.title ??
                                                ActivitiesComponentStrings
                                                    .textUntitledActivity,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14),
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            '${timeFormatter.format(assignment.startTime!.toLocal())} – ${timeFormatter.format(assignment.endTime!.toLocal())}',
                                            style: TextStyle(
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                                fontWeight: FontWeight.w500),
                                          ),
                                          if (assignment.places.isNotEmpty ||
                                              assignment.events.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  ...assignment.places
                                                      .map((p) => Chip(
                                                            label: Text(
                                                                p.title ?? '?'),
                                                            onDeleted: () =>
                                                                setState(() => widget
                                                                    .onRemoveLink(
                                                                        assignment,
                                                                        p)),
                                                          )),
                                                  ...assignment.events
                                                      .map((e) => Chip(
                                                            label: Text(
                                                                e.title ?? '?'),
                                                            onDeleted: () =>
                                                                setState(() => widget
                                                                    .onRemoveLink(
                                                                        assignment,
                                                                        e)),
                                                          )),
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: null,
    );
  }
}

class _UserSearchDialog extends StatefulWidget {
  final List<ActivityUserInfoModel> allUsers;
  const _UserSearchDialog({required this.allUsers});

  @override
  State<_UserSearchDialog> createState() => _UserSearchDialogState();
}

class _UserSearchDialogState extends State<_UserSearchDialog> {
  late List<ActivityUserInfoModel> _filteredUsers;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filteredUsers = List.from(widget.allUsers);
    _searchController.addListener(_filterUsers);
  }

  @override
  void dispose() {
    _searchController.removeListener(_filterUsers);
    _searchController.dispose();
    super.dispose();
  }

  void _filterUsers() {
    final query = _searchController.text;
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = List.from(widget.allUsers);
      });
    } else {
      final normalizedQuery = Utilities.removeDiacritics(query.toLowerCase());
      setState(() {
        _filteredUsers = widget.allUsers.where((user) {
          final normalizedName =
              Utilities.removeDiacritics(user.toFullNameString().toLowerCase());
          return normalizedName.contains(normalizedQuery);
        }).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(ActivitiesComponentStrings.dialogTitleSelectTargetUser),
      content: SizedBox(
        width: 300,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: ActivitiesComponentStrings.hintSearchUsers,
                prefixIcon: Icon(Icons.search),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  return ListTile(
                    title: Text(user.toFullNameString()),
                    onTap: () => Navigator.of(context).pop(user),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
