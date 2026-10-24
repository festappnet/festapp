import 'dart:async';
import 'package:auto_route/auto_route.dart';
import 'package:fstapp/app_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fstapp/components/navigation/root_route_navigation.dart';
import 'package:fstapp/components/navigation/route_visibility.dart';
import 'package:fstapp/components/notification_center/notification_detail_target.dart';
import '../../support/navigation_fixture.dart';
import '../navigation/routed_tab_navigation_cases.dart' show mount;

void main() {
  testWidgets(
      'retained order screens consume only the visible owner target and preserve filters',
      (tester) async {
    final router = FixtureRouter(Access());
    final contexts = <String, BuildContext>{};
    router.ordersCurrentBuilder = (context) {
      final link = context.routeData.inheritedPathParams
          .getString(AppRouter.linkFormatted);
      contexts[link] = context;
      return Text('Order screen $link');
    };
    const a =
        '/occasion-a/reservations/orders/current?orderId=1&orderMessageId=source-a&filter=one&filter=two';
    const b =
        '/occasion-b/reservations/orders/current?orderId=1&orderMessageId=source-b&filter=three';
    await mount(tester, router, a);
    final first = contexts['occasion-a']!;
    final firstMatchId = first.routeData.route.id;
    unawaited(pushRootPath(router, b));
    await tester.pumpAndSettle();
    expect(contexts.length, 2);
    expect(router.currentSegments.any((match) => match.id == firstMatchId),
        isFalse);
    expect(isVisibleRouteInstance(contexts['occasion-b']!), isTrue);
    // The same order value on a retained screen must not authorize its closure.
    if (first.mounted &&
        router.currentSegments.any((match) => match.id == firstMatchId)) {
      unawaited(clearNotificationDetailTarget(first, 'orderId', '1',
          companions: {'orderMessageId': 'source-a'}));
    }
    expect(router.urlState.uri.queryParameters['orderMessageId'], 'source-b');
    unawaited(clearNotificationDetailTarget(
        contexts['occasion-b']!, 'orderId', '1',
        companions: {'orderMessageId': 'source-b'}));
    await tester.pumpAndSettle();
    expect(router.urlState.uri.queryParameters, {'filter': 'three'});
    unawaited(pushRootPath(router, b));
    await tester.pumpAndSettle();
    expect(router.urlState.uri.queryParameters['orderId'], '1');
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
