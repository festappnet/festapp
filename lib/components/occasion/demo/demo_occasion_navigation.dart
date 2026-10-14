import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:fstapp/data_services/rights_service.dart';
import 'package:fstapp/components/unit/unit_model.dart';
import 'package:fstapp/router_service.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';

/// Demo events use the ordinary reservation shell and retain their list origin.
class DemoOccasionNavigation {
  static const returnQuery = 'demoReturnTo';

  static Future<void> open(BuildContext context, String link) =>
      RouterService.navigateToOccasionReservationsByLink(context, link,
          queryParameters: {
            returnQuery: context.router.root.urlState.uri.toString(),
          });

  static String returnPath(String? origin, Iterable<int> ownUnits) {
    final uri = origin == null ? null : Uri.tryParse(origin);
    final unit = uri == null
        ? null
        : RegExp(r'^/unit/([0-9]+)/edit/occasions/?$').firstMatch(uri.path);
    if (uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        (uri.path == '/' ||
            (unit != null &&
                ownUnits.contains(int.tryParse(unit.group(1)!))))) {
      return uri.toString();
    }
    return ownUnits.isEmpty ? '/' : '/unit/${ownUnits.first}/edit/occasions';
  }

  static UnitModel? originUnit(String? origin, List<UnitModel> ownUnits) {
    final path =
        returnPath(origin, ownUnits.map((unit) => unit.id).whereType<int>());
    final match = RegExp(r'^/unit/([0-9]+)/edit/occasions/?$')
        .firstMatch(Uri.parse(path).path);
    final id = int.tryParse(match?.group(1) ?? '');
    for (final unit in ownUnits) {
      if (unit.id == id && id != null) return unit;
    }
    return ownUnits.isEmpty ? null : ownUnits.first;
  }

  static UnitModel? breadcrumbUnit(BuildContext context) => originUnit(
      context.router.root.urlState.uri.queryParameters[returnQuery],
      RightsService.currentUser()?.units ?? []);

  static Future<void> back(BuildContext context) async {
    final path = returnPath(
        context.router.root.urlState.uri.queryParameters[returnQuery],
        (RightsService.currentUser()?.units ?? [])
            .map((unit) => unit.id)
            .whereType<int>());
    await context.router.root
        .navigate(rootRouteForPath(context.router.root, path));
  }
}
