import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';

/// Route names identify a page type; the native match ID identifies its instance.
/// Read the mounted controllers: browser history reparses URL matches with new
/// IDs while reusing existing pages, so urlState IDs can differ from theirs.
bool isVisibleRouteInstance(BuildContext context) =>
    context.router.root.currentSegments
        .any((match) => match.id == context.routeData.route.id);
