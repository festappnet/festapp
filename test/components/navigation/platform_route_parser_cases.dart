import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';

// Flutter 3.50 strips origin while preserving all URL escapes exactly.
String platformUrl(Uri uri) =>
    '${uri.path.isEmpty ? '/' : uri.path}'
    '${uri.hasQuery ? '?${uri.query}' : ''}'
    '${uri.hasFragment ? '#${uri.fragment}' : ''}';
void main() {
  test('Flutter 3.50 browser URL preserves the unencoded return target', () {
    const target =
        '/event-a/reservations/orders/current?day=2026-11-15&tag=a%2Bb#details';
    final uri = Uri(path: '/login', queryParameters: {'redirect': target});
    final parser = AppRouter().defaultRouteParser();
    final restored = parser.restoreRouteInformation(UrlState(uri, []));
    expect(restored.uri.queryParameters['redirect'], target);
  });
  test('login reload keeps the entire nested return URL across web transport', () async {
    const target =
        '/event-a/reservations/forms/second/responses?day=2026-10-03&preview-day=2026-10-10';
    final uri = Uri(path: '/login', queryParameters: {'redirect': target});
    final router = AppRouter();
    final parser = router.defaultRouteParser();
    final result = parser.restoreRouteInformation(UrlState(uri, []));
    final browserUri = Uri.parse(platformUrl(result.uri));
    expect(browserUri.queryParameters['redirect'], target);
    final restored = await parser.parseRouteInformation(
      AutoRouteInformation(uri: browserUri),
    );
    expect(restored.segments.last.queryParams.getString('redirect'), target);
  });
  test(
    'repeated query values and literal reserved characters survive transport',
    () {
      final uri = Uri(
        path: '/calendar',
        queryParameters: {
          'day': '2026-10-03',
          'tag': ['a b', 'a+b', 'a&b', '#?/%'],
        },
      );
      final parser = AppRouter().defaultRouteParser();
      final result = parser.restoreRouteInformation(
        UrlState(uri, [], shouldReplace: true),
      );
      expect(
        Uri.parse(platformUrl(result.uri)).queryParametersAll,
        uri.queryParametersAll,
      );
      expect((result as AutoRouteInformation).replace, isTrue);
    },
  );
  test('native transport uses the unchanged URI', () {
    final uri = Uri(
      path: '/login',
      queryParameters: {'redirect': '/event-a/admin?day=2026-10-03'},
    );
    final parser = AppRouter().defaultRouteParser();
    expect(parser.restoreRouteInformation(UrlState(uri, [])).uri, uri);
  });
}
