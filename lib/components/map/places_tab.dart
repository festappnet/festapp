import 'package:fstapp/components/navigation/navigation_paths.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/app_router.gr.dart';
import 'package:fstapp/components/navigation/routed_tab_scaffold.dart';
import 'package:fstapp/components/_shared/common_strings.dart';
import 'package:fstapp/components/map/map_strings.dart';
import 'package:fstapp/components/map/places_content.dart';
import 'package:fstapp/components/map/path_groups_content.dart';
import 'package:fstapp/components/icons/icons_management_widget.dart';
import 'package:fstapp/components/icons/place_types_content.dart';
import 'package:fstapp/components/icons/icons_strings.dart';

@RoutePage(name: 'PlacesTabsRoute')
class PlacesTab extends StatelessWidget {
  const PlacesTab({super.key});
  @override
  Widget build(BuildContext context) {
    Localizations.localeOf(context);
    return RoutedTabScaffold(tabs: [
      RoutedTabDefinition(
          slug: NavigationPaths.list,
          route: const PlacesListRoute(),
          label: CommonStrings.places,
          icon: Icons.place),
      RoutedTabDefinition(
          slug: NavigationPaths.paths,
          route: const PlacesPathsRoute(),
          label: MapStrings.paths,
          icon: Icons.timeline),
      RoutedTabDefinition(
          slug: NavigationPaths.types,
          route: const PlacesTypesRoute(),
          label: IconsStrings.placeTypes,
          icon: Icons.category_outlined),
      RoutedTabDefinition(
          slug: NavigationPaths.icons,
          route: const PlacesIconsRoute(),
          label: IconsStrings.icons,
          icon: Icons.emoji_symbols_outlined),
    ]);
  }
}

@RoutePage()
class PlacesListPage extends StatelessWidget {
  const PlacesListPage({super.key});
  @override
  Widget build(BuildContext context) => PlacesContent();
}

@RoutePage()
class PlacesPathsPage extends StatelessWidget {
  const PlacesPathsPage({super.key});
  @override
  Widget build(BuildContext context) => PathGroupsContent();
}

@RoutePage()
class PlacesTypesPage extends StatelessWidget {
  const PlacesTypesPage({super.key});
  @override
  Widget build(BuildContext context) => PlaceTypesContent();
}

@RoutePage()
class PlacesIconsPage extends StatelessWidget {
  const PlacesIconsPage({super.key});
  @override
  Widget build(BuildContext context) => IconsManagementWidget();
}
