import 'package:material_ui/material_ui.dart';
import 'package:fstapp/components/map/external_map_navigation.dart';
import 'package:fstapp/components/map/map_strings.dart';

class IosNavigationAppPicker extends StatelessWidget {
  final List<IosNavigationApp> apps;
  final String title;
  final ValueChanged<IosNavigationApp> onSelected;

  const IosNavigationAppPicker({
    super.key,
    required this.apps,
    required this.title,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            for (final app in apps)
              ListTile(
                leading: Icon(_icon(app)),
                title: Text(_name(app)),
                onTap: () => onSelected(app),
              ),
          ],
        ),
      );

  String _name(IosNavigationApp app) => switch (app) {
        IosNavigationApp.appleMaps => MapStrings.appleMaps,
        IosNavigationApp.googleMaps => MapStrings.googleMaps,
        IosNavigationApp.waze => MapStrings.waze,
        IosNavigationApp.mapyCom => MapStrings.mapyCom,
      };

  IconData _icon(IosNavigationApp app) => switch (app) {
        IosNavigationApp.appleMaps => Icons.map_outlined,
        IosNavigationApp.googleMaps => Icons.location_on_outlined,
        IosNavigationApp.waze => Icons.directions_car_outlined,
        IosNavigationApp.mapyCom => Icons.hiking_outlined,
      };
}
