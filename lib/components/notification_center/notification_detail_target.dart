import 'package:auto_route/auto_route.dart';
import 'package:flutter/widgets.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';

/// Closing a selected modal consumes only its own query target. Retained editors
/// and unrelated query values stay in the existing native route stack.
Future<void> clearNotificationDetailTarget(
    BuildContext context, String parameter, String value,
    {Map<String, String> companions = const {}}) async {
  final root = context.router.root;
  final uri = root.urlState.uri;
  if (uri.queryParameters[parameter] != value) return;
  final query = Map<String, List<String>>.of(uri.queryParametersAll)
    ..remove(parameter);
  for (final entry in companions.entries) {
    if (uri.queryParameters[entry.key] == entry.value) query.remove(entry.key);
  }
  final target = uri
      .replace(query: query.isEmpty ? '' : Uri(queryParameters: query).query)
      .toString();
  root.markUrlStateForReplace();
  await root.navigate(rootRouteForPath(root, target));
}
