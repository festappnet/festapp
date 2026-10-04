import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/groups/game_checkpoints_content.dart';
import 'package:fstapp/components/groups/group_strings.dart';
import 'package:fstapp/components/groups/game_settings_content.dart';
import 'package:fstapp/components/groups/game_user_groups_content.dart';
import 'package:fstapp/components/_shared/common_strings.dart';

@RoutePage(name: 'GameTabsRoute')
class GameTab extends StatelessWidget {
  const GameTab({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.checkpoints,
          route: const GameCheckpointsRoute(),
          label: GroupsStrings.checkPoints,
          icon: Icons.gamepad),
      RoutedTabDefinition(
          slug: NavigationPaths.groups,
          route: const GameGroupsRoute(),
          label: CommonStrings.groups,
          icon: Icons.groups),
      RoutedTabDefinition(
          slug: NavigationPaths.settings,
          route: const GameSettingsRoute(),
          label: CommonStrings.settings,
          icon: Icons.settings),
    ]);
  }
}

@RoutePage()
class GameCheckpointsPage extends StatelessWidget {
  const GameCheckpointsPage({super.key});
  @override
  Widget build(BuildContext context) => GameCheckPointsContent();
}

@RoutePage()
class GameGroupsPage extends StatelessWidget {
  const GameGroupsPage({super.key});
  @override
  Widget build(BuildContext context) => GameUserGroupsContent();
}

@RoutePage()
class GameSettingsPage extends StatelessWidget {
  const GameSettingsPage({super.key});
  @override
  Widget build(BuildContext context) => GameSettingsContent();
}
