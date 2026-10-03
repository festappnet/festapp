import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

/// Route names identify a page type; the native match ID identifies its instance.
/// IDs survive URL-state copies even when a retained route's children change.
bool isVisibleRouteInstance(BuildContext context) =>
    context.router.root.urlState.segments
        .any((match) => match.id == context.routeData.route.id);
