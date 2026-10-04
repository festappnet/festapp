import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'retained_draft_guard.dart';

/// External entries resolve at the root. A nested wildcard must never capture
/// an absolute path via AutoRoute's closest-matching-scope lookup.
PageRouteInfo rootRouteForPath(StackRouter root, String path) {
  final route = root.buildPageRoute(path, includePrefixMatches: false);
  if (route == null) throw FlutterError('Unknown root route: $path');
  return route;
}

bool _hasWildcard(List<RouteMatch> matches) => matches.any((match) =>
    match.path.endsWith('*') || _hasWildcard(match.children ?? const []));
Future<T?> pushRootPath<T extends Object?>(
    StackRouter root, String path) async {
  if (!await RetainedDraftGuard.instance.confirmPath(root, Uri.parse(path)))
    return null;
  final matches = root.matcher.match(path, includePrefixMatches: false);
  if (matches != null && _hasWildcard(matches)) {
    // AutoRoute's typed matcher expands '*' literally. Preserve the native
    // string match for a local not-found entry, just as PlatformDeepLink does.
    await root.navigateAll(matches);
    return null;
  }
  return root.push<T>(rootRouteForPath(root, path));
}

Future<T?> replaceRootPath<T extends Object?>(
    StackRouter root, String path) async {
  if (!await RetainedDraftGuard.instance.confirmPath(root, Uri.parse(path)))
    return null;
  final matches = root.matcher.match(path, includePrefixMatches: false);
  if (matches != null && _hasWildcard(matches)) {
    root.markUrlStateForReplace();
    await root.navigateAll(matches);
    return null;
  }
  return root.replace<T>(rootRouteForPath(root, path));
}
