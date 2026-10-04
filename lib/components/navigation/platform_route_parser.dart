import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Flutter 3.47's web navigation transport decodes query escapes once before
/// passing a URL to its platform strategy. Preserve them across that boundary;
/// AutoRoute still owns parsing, history and all route state.
class PlatformRouteParser extends DefaultRouteParser {
  final bool platformDecodesQueries;
  PlatformRouteParser(super.matcher,
      {super.includePrefixMatches,
      super.deepLinkTransformer,
      this.platformDecodesQueries = kIsWeb});

  @override
  RouteInformation restoreRouteInformation(UrlState configuration) {
    final information = super.restoreRouteInformation(configuration);
    if (!platformDecodesQueries || !information.uri.hasQuery)
      return information;
    final query = information.uri.queryParametersAll.map((key, values) =>
        MapEntry(Uri.encodeQueryComponent(key),
            values.map(Uri.encodeQueryComponent).toList()));
    return AutoRouteInformation(
        uri: information.uri.replace(queryParameters: query),
        replace: configuration.shouldReplace,
        state: configuration.pathState);
  }
}
