import 'package:flutter/widgets.dart';
import 'package:fstapp/components/map/map_page.dart';
import 'package:fstapp/components/map/public_map_host.dart';
import 'package:fstapp/components/map/public_map_session.dart';
import 'package:fstapp/router_service.dart';

/// Canonical navigation boundary for opening a place on the occasion map.
abstract final class MapNavigation {
  static Future<MapVisitResult> openPlace(
    BuildContext context,
    int placeId,
  ) async {
    final session = PublicMapSessionScope.read(context);
    if (session != null) return session.openPlace(placeId);

    return _openCold(context, '${MapPage.ROUTE}/$placeId');
  }

  static Future<MapVisitResult> openCategory(
    BuildContext context,
    String placeType,
  ) async {
    final session = PublicMapSessionScope.read(context);
    if (session != null) return session.openCategory(placeType);

    final encoded = Uri.encodeQueryComponent(placeType);
    return _openCold(context, '${MapPage.ROUTE}?placeType=$encoded');
  }

  static Future<MapVisitResult> _openCold(
    BuildContext context,
    String route,
  ) async {
    try {
      await RouterService.navigateOccasion<void>(context, route);
      return const MapVisitResult.returned(
        MapFocusOutcome.cancelled('coldRouteOwnsFocusOutcome'),
      );
    } catch (error) {
      return MapVisitResult.navigationFailed(error.toString());
    }
  }
}
