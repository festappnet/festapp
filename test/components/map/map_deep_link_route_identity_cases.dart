import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/app_router.dart';

void main() {
  test('place deep link resolves one public map route and no editor route', () {
    final matches = AppRouter().matcher.match('/demo/map/42');

    expect(matches, isNotNull);
    final flattened = _flatten(matches!);
    expect(
      flattened.where((match) => match.name == 'PublicMapRoute'),
      hasLength(1),
    );
    expect(
      flattened.where((match) => match.name == 'MapEditorRoute'),
      isEmpty,
    );
    final adapter =
        flattened.singleWhere((match) => match.name == 'PublicMapRoute');
    expect(adapter.pathParams.getString('destination'), '42');
  });

  test('category query remains a thin public route compatibility boundary', () {
    final matches = AppRouter().matcher.match('/demo/map?placeType=wc');

    expect(matches, isNotNull);
    final public = _flatten(matches!)
        .singleWhere((match) => match.name == 'PublicMapRoute');
    expect(public.pathParams.getString('destination'), 'overview');
    expect(public.queryParams.getString('placeType'), 'wc');
  });
}

Iterable<RouteMatch> _flatten(List<RouteMatch> matches) sync* {
  for (final match in matches) {
    yield match;
    yield* _flatten(match.children ?? const []);
  }
}
