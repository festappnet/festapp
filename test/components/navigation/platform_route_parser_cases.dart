import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';
import 'package:fstapp/components/navigation/platform_route_parser.dart';

// The pinned Flutter web engine reconstructs Uri from the query map, then
// decodes it once before handing it to UrlStrategy. Test the resulting public
// URL and parser round trip, not just an intermediate escaped string.
String platformUrl(Uri uri) => Uri.decodeComponent(
    Uri(path: uri.path, queryParameters: uri.queryParametersAll).toString());
void main() {
  test('login reload keeps the entire nested return URL across web transport',
      () async {
    const target =
        '/event-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    final uri = Uri(path: '/login', queryParameters: {'redirect': target});
    final router = AppRouter();
    final parser =
        PlatformRouteParser(router.matcher, platformDecodesQueries: true);
    final result = parser.restoreRouteInformation(UrlState(uri, []));
    final browserUri = Uri.parse(platformUrl(result.uri));
    expect(browserUri.queryParameters['redirect'], target);
    final restored = await parser
        .parseRouteInformation(AutoRouteInformation(uri: browserUri));
    expect(restored.segments.last.queryParams.getString('redirect'), target);
  });
  test(
      'repeated query values and literal reserved characters survive transport',
      () {
    final uri = Uri(path: '/calendar', queryParameters: {
      'day': '2026-10-03',
      'tag': ['a b', 'a+b', 'a&b', '#?/%']
    });
    final parser =
        PlatformRouteParser(AppRouter().matcher, platformDecodesQueries: true);
    final result =
        parser.restoreRouteInformation(UrlState(uri, [], shouldReplace: true));
    expect(Uri.parse(platformUrl(result.uri)).queryParametersAll,
        uri.queryParametersAll);
    expect((result as AutoRouteInformation).replace, isTrue);
  });
  test('native transport uses the unchanged URI', () {
    final uri = Uri(
        path: '/login',
        queryParameters: {'redirect': '/event-a/admin?day=2026-10-03'});
    final parser =
        PlatformRouteParser(AppRouter().matcher, platformDecodesQueries: false);
    expect(parser.restoreRouteInformation(UrlState(uri, [])).uri, uri);
  });
}
