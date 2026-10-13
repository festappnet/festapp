import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/components/groups/group_participant_model.dart';
import 'package:fstapp/components/groups/user_group_info_model.dart';
import 'package:fstapp/components/users/user_info_model.dart';
import 'package:fstapp/services/utilities_all.dart';
import 'package:fstapp/styles/styles_config.dart';

import 'group_strings.dart';

class ParticipantsManagementDialog extends StatefulWidget {
  final UserGroupInfoModel group;
  final List<UserInfoModel> allUsers;
  final Set<String> allAssignedUserIds;

  const ParticipantsManagementDialog({
    super.key,
    required this.group,
    required this.allUsers,
    required this.allAssignedUserIds,
  });

  @override
  State<ParticipantsManagementDialog> createState() =>
      _ParticipantsManagementDialogState();
}

class _ParticipantsManagementDialogState
    extends State<ParticipantsManagementDialog> {
  final _searchController = TextEditingController();

  late List<UserInfoModel> _baseAvailableUsers;
  late List<UserInfoModel> _filteredAvailableUsers;

  @override
  void initState() {
    super.initState();
    widget.group.participants ??= {};

    final currentGroupIds =
        widget.group.participants!.map((p) => p.userInfo!.id).toSet();

    _baseAvailableUsers = widget.allUsers.where((user) {
      final isAssignedElsewhere = widget.allAssignedUserIds.contains(user.id);
      final isInThisGroup = currentGroupIds.contains(user.id);
      return !isAssignedElsewhere || isInThisGroup;
    }).toList();

    _filteredAvailableUsers = List.from(_baseAvailableUsers);

    _searchController.addListener(_applyFilter);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  void _applyFilter() {
    final query = _searchController.text;
    setState(() {
      if (query.isEmpty) {
        _filteredAvailableUsers = List.from(_baseAvailableUsers);
        return;
      }
      final normalizedQuery = Utilities.removeDiacritics(query).toLowerCase();
      _filteredAvailableUsers = _baseAvailableUsers.where((user) {
        final normalizedName =
            Utilities.removeDiacritics(user.toFullNameString()).toLowerCase();
        final normalizedSecondary =
            Utilities.removeDiacritics(user.getSecondaryInfoString(context))
                .toLowerCase();

        return normalizedName.contains(normalizedQuery) ||
            normalizedSecondary.contains(normalizedQuery);
      }).toList();
    });
  }

  void _removeParticipant(GroupParticipantModel participant) {
    setState(() {
      widget.group.participants!.remove(participant);
      if (participant.userInfo != null) {
        _baseAvailableUsers.add(participant.userInfo!);
        _baseAvailableUsers.sort(
            (a, b) => a.toFullNameString().compareTo(b.toFullNameString()));
      }
      _applyFilter();
    });
  }

  void _addParticipant(UserInfoModel user, {bool isLeader = false}) {
    setState(() {
      if (isLeader) {
        _demoteCurrentLeader();
      }
      widget.group.participants!.removeWhere((p) => p.userInfo?.id == user.id);
      widget.group.participants!
          .add(GroupParticipantModel(userInfo: user, isAdmin: isLeader));

      _baseAvailableUsers.removeWhere((u) => u.id == user.id);
      _applyFilter();
    });
  }

  void _promoteToLeader(GroupParticipantModel newLeader) {
    setState(() {
      _demoteCurrentLeader();
      newLeader.isAdmin = true;
    });
  }

  void _handleDemoteLeader() {
    setState(() {
      _demoteCurrentLeader();
    });
  }

  void _demoteCurrentLeader() {
    final oldLeader =
        widget.group.participants?.firstWhereOrNull((p) => p.isAdmin == true);
    if (oldLeader != null) {
      oldLeader.isAdmin = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.group.participants?.length ?? 0;
    final leader =
        widget.group.participants?.firstWhereOrNull((p) => p.isAdmin == true);
    final members =
        widget.group.participants?.where((p) => p.isAdmin != true).toList() ??
            [];
    members.sort((a, b) => a.userInfo!
        .toFullNameString()
        .compareTo(b.userInfo!.toFullNameString()));

    // Define a breakpoint and set flex factors based on screen width.
    const double desktopBreakpoint = 800.0;
    final bool isDesktop =
        MediaQuery.of(context).size.width > desktopBreakpoint;

    final int topSectionFlex = 1;
    final int bottomSectionFlex = isDesktop ? 2 : 1;

    return AlertDialog(
      title: Text(GroupsStrings.dialogTitle(widget.group.title, count)),
      content: SizedBox(
        width: StylesConfig.formMaxWidthMid,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              // Apply the top flex factor
              flex: topSectionFlex,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle(GroupsStrings.sectionLeader),
                    leader != null
                        ? _buildParticipantChip(
                            context: context,
                            participant: leader,
                            isLeader: true,
                            onPromote: () {},
                            onDemote: _handleDemoteLeader,
                            onRemove: () => _removeParticipant(leader),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(GroupsStrings.noLeaderSelected,
                                style: const TextStyle(
                                    fontStyle: FontStyle.italic)),
                          ),
                    const SizedBox(height: 8),
                    _buildSectionTitle(GroupsStrings.sectionMembers),
                    Wrap(
                      spacing: 8.0,
                      runSpacing: 8.0,
                      children: members
                          .map((p) => _buildParticipantChip(
                                context: context,
                                participant: p,
                                isLeader: false,
                                onPromote: () => _promoteToLeader(p),
                                onDemote: () {},
                                onRemove: () => _removeParticipant(p),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 24),
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                  hintText: GroupsStrings.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: const OutlineInputBorder(),
                  isDense: true),
            ),
            Expanded(
              // Apply the bottom flex factor
              flex: bottomSectionFlex,
              child: ListView.builder(
                itemCount: _filteredAvailableUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredAvailableUsers[index];
                  final secondaryText = user.getSecondaryInfoString(context);
                  return ListTile(
                    title: Text(
                      user.toFullNameString(),
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: secondaryText.isNotEmpty
                        ? Text(
                            secondaryText,
                            style:
                                TextStyle(color: Theme.of(context).hintColor),
                          )
                        : null,
                    trailing: ElevatedButton(
                        onPressed: () => _addParticipant(user),
                        child: Text(GroupsStrings.buttonAdd)),
                  );
                },
              ),
            )
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(GroupsStrings.buttonClose))
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(title, style: Theme.of(context).textTheme.titleMedium),
    );
  }

  Widget _buildParticipantChip({
    required BuildContext context,
    required GroupParticipantModel participant,
    required bool isLeader,
    required VoidCallback onPromote,
    required VoidCallback onDemote,
    required VoidCallback onRemove,
  }) {
    final chipTheme = Theme.of(context).chipTheme;
    final secondaryInfo = participant.userInfo!.getSecondaryInfoString(context);

    return Tooltip(
      message: secondaryInfo.isNotEmpty
          ? secondaryInfo
          : participant.userInfo!.toFullNameString(),
      child: Container(
        height: 32.0,
        decoration: BoxDecoration(
          color: chipTheme.backgroundColor ??
              Theme.of(context).disabledColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 8),
            isLeader
                ? IconButton(
                    icon: const Icon(Icons.star),
                    color: Colors.amber.shade700,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                    tooltip: GroupsStrings.demoteLeaderTooltip,
                    onPressed: onDemote,
                  )
                : IconButton(
                    icon: const Icon(Icons.star_outline),
                    color: Theme.of(context).disabledColor,
                    iconSize: 20,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    splashRadius: 16,
                    tooltip: GroupsStrings.assignLeaderTooltip,
                    onPressed: onPromote,
                  ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Text(participant.userInfo!.toFullNameString()),
            ),
            IconButton(
              icon: const Icon(Icons.cancel),
              iconSize: 20,
              color:
                  chipTheme.deleteIconColor ?? Theme.of(context).disabledColor,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              splashRadius: 16,
              tooltip: GroupsStrings.removeParticipantTooltip,
              onPressed: onRemove,
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
