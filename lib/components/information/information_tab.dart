import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/information/information_strings.dart';
import 'package:fstapp/components/features/feature_constants.dart';
import 'package:fstapp/components/features/feature_service.dart';
import 'package:fstapp/components/information/information_content.dart';
import 'package:fstapp/components/information/song/songbook_content.dart';

@RoutePage(name: 'InformationTabsRoute')
class InformationTab extends StatelessWidget {
  const InformationTab({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.information,
          route: const InformationInformationRoute(),
          label: InformationStrings.information,
          icon: Icons.info),
      if (FeatureService.isFeatureEnabled(FeatureConstants.songbook))
        RoutedTabDefinition(
            slug: NavigationPaths.songbook,
            route: const InformationSongbookRoute(),
            label: CommonStrings.songbook,
            icon: Icons.library_music),
    ]);
  }
}

@RoutePage()
class InformationInformationPage extends StatelessWidget {
  const InformationInformationPage({super.key});
  @override
  Widget build(BuildContext context) => InformationContent();
}

@RoutePage()
class InformationSongbookPage extends StatelessWidget {
  const InformationSongbookPage({super.key});
  @override
  Widget build(BuildContext context) => SongbookContent();
}
